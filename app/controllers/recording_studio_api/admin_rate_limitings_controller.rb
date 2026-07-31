# frozen_string_literal: true

module RecordingStudioApi
  class AdminRateLimitingsController < AdminController
    def show
      configuration = RecordingStudioApi.configuration
      api = @current_admin_api

      @rate_limit_rows = [
        setting_row("Rate limit OAuth enabled", format_boolean(api.rate_limit_oauth_enabled)),
        setting_row("Rate limit OAuth requests", format_number(api.rate_limit_oauth_requests)),
        setting_row("Rate limit OAuth period", format_seconds(api.rate_limit_oauth_period_seconds)),
        setting_row("Rate limit API pre-auth enabled", format_boolean(api.rate_limit_api_pre_auth_enabled)),
        setting_row("Rate limit API pre-auth requests", format_number(api.rate_limit_api_pre_auth_requests)),
        setting_row("Rate limit API pre-auth period", format_seconds(api.rate_limit_api_pre_auth_period_seconds)),
        setting_row("Rate limit API enabled", format_boolean(api.rate_limit_api_enabled)),
        setting_row("Rate limit API read requests", format_number(api.rate_limit_api_read_requests)),
        setting_row("Rate limit API read period", format_seconds(api.rate_limit_api_read_period_seconds)),
        setting_row("Rate limit API write requests", format_number(api.rate_limit_api_write_requests)),
        setting_row("Rate limit API write period", format_seconds(api.rate_limit_api_write_period_seconds)),
        setting_row("Rate limit Redis URL", format_presence(configuration.rate_limit_redis_url)),
        setting_row("Rate limit Redis namespace", format_presence(configuration.rate_limit_redis_namespace))
      ]
      @api_label = api.name.humanize
    end

    private

    def setting_row(setting, value)
      { setting: setting, value: value }
    end

    def format_boolean(value)
      value ? "Enabled" : "Disabled"
    end

    def format_presence(value)
      normalized = value.to_s.strip
      normalized.present? ? normalized : "Not set"
    end

    def format_number(value)
      value.to_i.to_s
    end

    def format_seconds(value)
      "#{value.to_i} seconds"
    end
  end
end
