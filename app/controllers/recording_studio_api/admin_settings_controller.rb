# frozen_string_literal: true

module RecordingStudioApi
  class AdminSettingsController < AdminController
    def show
      configuration = RecordingStudioApi.configuration

      @settings_rows = [
        setting_row("API versions", format_list(configuration.api_versions)),
        setting_row("Default API version", format_value(configuration.default_api_version)),
        setting_row("Request timeout", format_seconds(configuration.timeout)),
        setting_row("Token TTL", format_seconds(configuration.token_ttl)),
        setting_row("API request logging enabled", format_boolean(configuration.api_request_logging_enabled)),
        setting_row("API request logging payload mode", format_presence(configuration.api_request_logging_payload_mode))
      ]
    end

    private

    def setting_row(setting, value)
      { setting: setting, value: value }
    end

    def format_boolean(value)
      value ? "Enabled" : "Disabled"
    end

    def format_list(value)
      values = Array(value).map { |entry| entry.to_s.strip }.reject(&:blank?)
      return "Not set" if values.empty?

      values.join(", ")
    end

    def format_presence(value)
      normalized = value.to_s.strip
      normalized.present? ? normalized : "Not set"
    end

    def format_value(value)
      format_presence(value)
    end

    def format_seconds(value)
      "#{value.to_i} seconds"
    end
  end
end
