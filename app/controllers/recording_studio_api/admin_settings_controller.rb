# frozen_string_literal: true

module RecordingStudioApi
  class AdminSettingsController < AdminController
    before_action :authorize_api_access_update!, only: :update_api_access

    def show
      configuration = RecordingStudioApi.configuration

      @api_setting = RecordingStudioApi::ApiSetting.for_api(@current_admin_api.name)
      @api_access_enabled = @api_setting.api_access_enabled
      @api_label = @current_admin_api.name.humanize

      @settings_rows = [
        setting_row("Configured APIs", format_list(configuration.api_names)),
        *configuration.each_api.flat_map do |api|
          label = api.name.humanize
          [
            setting_row("#{label} API versions", format_list(api.api_versions)),
            setting_row("#{label} default API version", format_value(api.default_api_version))
          ]
        end,
        setting_row("Request timeout", format_seconds(configuration.timeout)),
        setting_row("Credential TTL", format_seconds(@current_admin_api.credential_ttl)),
        setting_row("Access token TTL", format_seconds(@current_admin_api.access_token_ttl)),
        setting_row("API request logging enabled", format_boolean(@current_admin_api.api_request_logging_enabled)),
        setting_row("API request logging payload mode", format_presence(@current_admin_api.api_request_logging_payload_mode)),
        setting_row("API request log retention", format_days(configuration.api_request_log_retention_days)),
        setting_row("API daily metric retention", format_days(configuration.api_daily_metric_retention_days))
      ]
    end

    def update_api_access
      api_setting = RecordingStudioApi::ApiSetting.for_api(@current_admin_api.name)
      api_setting.update!(api_access_enabled: api_access_params.fetch(:enabled, "0"))

      redirect_to RecordingStudioApi.admin_settings_path(
        controller: self,
        **RecordingStudioApi::Admin::ApiContext.query_params(@current_admin_api.name),
        **page_nav_close_param
      ), notice: api_access_notice(api_setting)
    end

    private

    def authorize_api_access_update!
      return if RecordingStudioAccessible.authorized?(
        actor: current_request_actor,
        recording: @admin_api_recording,
        role: RecordingStudioApi.configuration.access_management_edit_role
      )

      raise RecordingStudioApi::AuthorizationError, "Editing API access is not available for the current actor"
    end

    def api_access_params
      params.fetch(:api_access, {}).permit(:enabled)
    end

    def api_access_notice(api_setting)
      api_setting.api_access_enabled? ? "API access enabled." : "API access disabled."
    end

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

    def format_days(value)
      return "Indefinite" if value.nil?

      "#{value} days"
    end
  end
end
