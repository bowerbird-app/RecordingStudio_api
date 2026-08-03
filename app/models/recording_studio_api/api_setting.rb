# frozen_string_literal: true

module RecordingStudioApi
  class ApiSetting < ApplicationRecord
    self.table_name = "recording_studio_api_api_settings"

    validates :key, presence: true, uniqueness: true

    def self.for_api(api = :public)
      api_key = RecordingStudioApi.configuration.fetch_api(api).name
      find_or_initialize_by(key: api_key == "public" ? "api" : "api:#{api_key}")
    end

    def self.api_access_enabled?(api: :public)
      return true unless connection.data_source_exists?(table_name)

      global_enabled = find_by(key: "api")&.api_access_enabled != false
      api_key = RecordingStudioApi.configuration.fetch_api(api).name
      return global_enabled if api_key == "public"

      global_enabled && for_api(api_key).api_access_enabled != false
    rescue ActiveRecord::StatementInvalid
      false
    end
  end
end