# frozen_string_literal: true

module RecordingStudioApi
  # Resolves effective per-API operational policy: ApiSetting runtime overrides
  # layered on top of initializer / ApiDefinition defaults.
  class ApiRuntimePolicy
    PER_API_BOOLEAN_KEYS = %w[
      api_request_logging_enabled
      rate_limit_oauth_enabled
      rate_limit_api_enabled
      rate_limit_api_pre_auth_enabled
    ].freeze

    PER_API_INTEGER_KEYS = %w[
      credential_ttl_seconds
      access_token_ttl_seconds
      rate_limit_oauth_requests
      rate_limit_oauth_period_seconds
      rate_limit_api_pre_auth_requests
      rate_limit_api_pre_auth_period_seconds
      rate_limit_api_read_requests
      rate_limit_api_read_period_seconds
      rate_limit_api_write_requests
      rate_limit_api_write_period_seconds
    ].freeze

    GLOBAL_INTEGER_KEYS = %w[
      api_request_log_retention_days
      api_daily_metric_retention_days
    ].freeze

    PER_API_KEYS = (PER_API_BOOLEAN_KEYS + PER_API_INTEGER_KEYS).freeze
    ALL_KEYS = (PER_API_KEYS + GLOBAL_INTEGER_KEYS).freeze

    class << self
      def for(api = :public)
        new(api)
      end
    end

    def initialize(api = :public)
      @definition = RecordingStudioApi.configuration.fetch_api(api)
      @api_key = @definition.name
      @setting = safe_setting_for(@api_key)
      @global_setting = safe_setting_for("public")
    end

    attr_reader :api_key, :definition

    def api_request_logging_enabled
      boolean_override("api_request_logging_enabled") { definition.api_request_logging_enabled }
    end

    def api_request_logging_payload_mode
      definition.api_request_logging_payload_mode
    end

    def api_request_log_allowed_param_keys
      definition.api_request_log_allowed_param_keys
    end

    def credential_ttl
      duration_override("credential_ttl_seconds") { definition.credential_ttl }
    end

    def access_token_ttl
      duration_override("access_token_ttl_seconds") { definition.access_token_ttl }
    end

    def rate_limit_oauth_enabled
      boolean_override("rate_limit_oauth_enabled") { definition.rate_limit_oauth_enabled }
    end

    def rate_limit_api_enabled
      boolean_override("rate_limit_api_enabled") { definition.rate_limit_api_enabled }
    end

    def rate_limit_api_pre_auth_enabled
      boolean_override("rate_limit_api_pre_auth_enabled") { definition.rate_limit_api_pre_auth_enabled }
    end

    def rate_limit_oauth_requests
      integer_override("rate_limit_oauth_requests") { definition.rate_limit_oauth_requests }
    end

    def rate_limit_oauth_period_seconds
      integer_override("rate_limit_oauth_period_seconds") { definition.rate_limit_oauth_period_seconds }
    end

    def rate_limit_api_pre_auth_requests
      integer_override("rate_limit_api_pre_auth_requests") { definition.rate_limit_api_pre_auth_requests }
    end

    def rate_limit_api_pre_auth_period_seconds
      integer_override("rate_limit_api_pre_auth_period_seconds") { definition.rate_limit_api_pre_auth_period_seconds }
    end

    def rate_limit_api_requests
      definition.rate_limit_api_requests
    end

    def rate_limit_api_period_seconds
      definition.rate_limit_api_period_seconds
    end

    def rate_limit_api_read_requests
      integer_override("rate_limit_api_read_requests") { definition.rate_limit_api_read_requests }
    end

    def rate_limit_api_read_period_seconds
      integer_override("rate_limit_api_read_period_seconds") { definition.rate_limit_api_read_period_seconds }
    end

    def rate_limit_api_write_requests
      integer_override("rate_limit_api_write_requests") { definition.rate_limit_api_write_requests }
    end

    def rate_limit_api_write_period_seconds
      integer_override("rate_limit_api_write_period_seconds") { definition.rate_limit_api_write_period_seconds }
    end

    def api_request_log_retention_days
      global_integer_override("api_request_log_retention_days") do
        RecordingStudioApi.configuration.api_request_log_retention_days
      end
    end

    def api_daily_metric_retention_days
      global_integer_override("api_daily_metric_retention_days") do
        RecordingStudioApi.configuration.api_daily_metric_retention_days
      end
    end

    def override?(key)
      overrides.key?(key.to_s)
    end

    def overrides
      return {} if @setting.nil?

      @setting.runtime_overrides_hash
    end

    def global_overrides
      return {} if @global_setting.nil?

      @global_setting.runtime_overrides_hash
    end

    private

    def boolean_override(key)
      value = overrides[key]
      return yield if value.nil?

      ::ActiveModel::Type::Boolean.new.cast(value)
    end

    def integer_override(key)
      value = overrides[key]
      return yield if value.nil?

      Integer(value)
    end

    def duration_override(key)
      value = overrides[key]
      return yield if value.nil?

      Integer(value).seconds
    end

    def safe_setting_for(api)
      return unless defined?(::ActiveRecord::Base)
      return unless ApiSetting.table_available?
      return unless ApiSetting.runtime_overrides_supported?

      ApiSetting.for_api(api)
    rescue StandardError
      nil
    end

    def global_integer_override(key)
      value = global_overrides[key]
      return yield if value.nil?
      return nil if ["indefinite", false].include?(value)

      Integer(value)
    end
  end
end
