# frozen_string_literal: true

module RecordingStudioApi
  class AdminSettingsController < AdminController
    before_action :authorize_api_access_update!, only: %i[update_api_access update_runtime_policy]

    def show
      configuration = RecordingStudioApi.configuration
      @policy = RecordingStudioApi::ApiRuntimePolicy.for(@current_admin_api.name)
      @api_setting = RecordingStudioApi::ApiSetting.for_api(@current_admin_api.name)
      @api_access_enabled = @api_setting.api_access_enabled
      @api_label = @current_admin_api.name.humanize
      @overrides = @api_setting.runtime_overrides_hash
      @global_overrides = RecordingStudioApi::ApiSetting.for_api(:public).runtime_overrides_hash

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
        setting_row("Credential TTL (effective)", format_seconds(@policy.credential_ttl)),
        setting_row("Access token TTL (effective)", format_seconds(@policy.access_token_ttl)),
        setting_row("API request logging enabled (effective)", format_boolean(@policy.api_request_logging_enabled)),
        setting_row("API request logging payload mode", format_presence(@policy.api_request_logging_payload_mode)),
        setting_row("API request log retention (effective)", format_days(@policy.api_request_log_retention_days)),
        setting_row("API daily metric retention (effective)", format_days(@policy.api_daily_metric_retention_days))
      ]
    end

    def update_api_access
      api_setting = RecordingStudioApi::ApiSetting.for_api(@current_admin_api.name)
      api_setting.update!(api_access_enabled: api_access_params.fetch(:enabled, "0"))

      redirect_to settings_redirect_path, notice: api_access_notice(api_setting)
    end

    def update_runtime_policy
      api_setting = RecordingStudioApi::ApiSetting.for_api(@current_admin_api.name)
      attrs = runtime_policy_params
      attrs = attrs.merge(global_retention_params) if @current_admin_api.name == "public"
      api_setting.apply_runtime_overrides!(attrs)

      redirect_to settings_redirect_path, notice: "Runtime policy overrides saved."
    rescue ArgumentError, TypeError, ActiveRecord::RecordInvalid => e
      redirect_to settings_redirect_path, alert: "Could not save runtime policy: #{e.message}"
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

    def runtime_policy_params
      params.fetch(:runtime_policy, {}).permit(
        :api_request_logging_enabled,
        :credential_ttl_seconds,
        :access_token_ttl_seconds
      ).to_h
    end

    def global_retention_params
      params.fetch(:runtime_policy, {}).permit(
        :api_request_log_retention_days,
        :api_daily_metric_retention_days
      ).to_h
    end

    def settings_redirect_path
      RecordingStudioApi.admin_settings_path(
        controller: self,
        **RecordingStudioApi::Admin::ApiContext.query_params(@current_admin_api.name),
        **page_nav_close_param
      )
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
