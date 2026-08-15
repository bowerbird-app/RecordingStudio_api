# frozen_string_literal: true

module RecordingStudioApi
  class ApiSetting < ApplicationRecord
    self.table_name = "recording_studio_api_api_settings"

    validates :key, presence: true, uniqueness: true
    validate :runtime_overrides_must_be_allowed

    class << self
      def for_api(api = :public)
        api_key = RecordingStudioApi.configuration.fetch_api(api).name
        find_or_initialize_by(key: api_key == "public" ? "api" : "api:#{api_key}")
      end

      def api_access_enabled?(api: :public)
        return true unless table_available?

        global_enabled = find_by(key: "api")&.api_access_enabled != false
        api_key = RecordingStudioApi.configuration.fetch_api(api).name
        return global_enabled if api_key == "public"

        global_enabled && for_api(api_key).api_access_enabled != false
      rescue ActiveRecord::StatementInvalid
        false
      end

      def table_available?
        connection.data_source_exists?(table_name)
      rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
        false
      end

      def runtime_overrides_supported?
        table_available? && column_names.include?("runtime_overrides")
      end
    end

    def runtime_overrides_hash
      return {} unless self.class.runtime_overrides_supported?

      raw = self[:runtime_overrides]
      return {} if raw.blank?

      raw.respond_to?(:deep_stringify_keys) ? raw.deep_stringify_keys : raw.to_h.transform_keys(&:to_s)
    end

    # Merge submitted admin values into runtime_overrides.
    # Blank strings clear an override so initializer defaults apply again.
    def apply_runtime_overrides!(attrs)
      raise ActiveRecord::StatementInvalid, "runtime_overrides column is unavailable" unless self.class.runtime_overrides_supported?

      next_overrides = runtime_overrides_hash.dup
      Array(attrs).each do |(key, value)|
        normalized_key = key.to_s
        next unless allowed_override_key?(normalized_key)

        if clear_override?(value)
          next_overrides.delete(normalized_key)
        else
          next_overrides[normalized_key] = normalize_override_value(normalized_key, value)
        end
      end

      self.runtime_overrides = next_overrides
      save!
    end

    private

    def allowed_override_key?(key)
      return true if ApiRuntimePolicy::PER_API_KEYS.include?(key)
      return true if global_settings_row? && ApiRuntimePolicy::GLOBAL_INTEGER_KEYS.include?(key)

      false
    end

    def global_settings_row?
      key == "api"
    end

    def clear_override?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?) || value.to_s.strip == ""
    end

    def normalize_override_value(key, value)
      if ApiRuntimePolicy::PER_API_BOOLEAN_KEYS.include?(key)
        ::ActiveModel::Type::Boolean.new.cast(value)
      elsif key == "api_daily_metric_retention_days" && value.to_s.strip == "indefinite"
        "indefinite"
      else
        Integer(value)
      end
    end

    def runtime_overrides_must_be_allowed
      return unless self.class.runtime_overrides_supported?

      runtime_overrides_hash.each_key do |key|
        errors.add(:runtime_overrides, "includes unsupported key #{key}") unless allowed_override_key?(key)
      end
    rescue ArgumentError, TypeError => e
      errors.add(:runtime_overrides, e.message)
    end
  end
end
