# frozen_string_literal: true

module RecordingStudioApi
  class AdminRateLimitingsController < AdminController
    before_action :authorize_rate_limit_update!, only: :update

    def show
      configuration = RecordingStudioApi.configuration
      @policy = RecordingStudioApi::ApiRuntimePolicy.for(@current_admin_api.name)
      @api_setting = RecordingStudioApi::ApiSetting.for_api(@current_admin_api.name)
      @overrides = @api_setting.runtime_overrides_hash
      @api_label = @current_admin_api.name.humanize

      @rate_limit_rows = [
        setting_row("Rate limit OAuth enabled (effective)", format_boolean(@policy.rate_limit_oauth_enabled)),
        setting_row("Rate limit OAuth requests (effective)", format_number(@policy.rate_limit_oauth_requests)),
        setting_row("Rate limit OAuth period (effective)", format_seconds(@policy.rate_limit_oauth_period_seconds)),
        setting_row("Rate limit API pre-auth enabled (effective)", format_boolean(@policy.rate_limit_api_pre_auth_enabled)),
        setting_row("Rate limit API pre-auth requests (effective)", format_number(@policy.rate_limit_api_pre_auth_requests)),
        setting_row("Rate limit API pre-auth period (effective)", format_seconds(@policy.rate_limit_api_pre_auth_period_seconds)),
        setting_row("Rate limit API enabled (effective)", format_boolean(@policy.rate_limit_api_enabled)),
        setting_row("Rate limit API read requests (effective)", format_number(@policy.rate_limit_api_read_requests)),
        setting_row("Rate limit API read period (effective)", format_seconds(@policy.rate_limit_api_read_period_seconds)),
        setting_row("Rate limit API write requests (effective)", format_number(@policy.rate_limit_api_write_requests)),
        setting_row("Rate limit API write period (effective)", format_seconds(@policy.rate_limit_api_write_period_seconds)),
        setting_row("Rate limit Redis URL", format_presence(configuration.rate_limit_redis_url)),
        setting_row("Rate limit Redis namespace", format_presence(configuration.rate_limit_redis_namespace))
      ]
    end

    def update
      api_setting = RecordingStudioApi::ApiSetting.for_api(@current_admin_api.name)
      api_setting.apply_runtime_overrides!(rate_limit_params)

      redirect_to rate_limiting_redirect_path, notice: "Rate limit overrides saved."
    rescue ArgumentError, TypeError, ActiveRecord::RecordInvalid => e
      redirect_to rate_limiting_redirect_path, alert: "Could not save rate limits: #{e.message}"
    end

    private

    def authorize_rate_limit_update!
      return if RecordingStudioAccessible.authorized?(
        actor: current_request_actor,
        recording: @admin_api_recording,
        role: RecordingStudioApi.configuration.access_management_edit_role
      )

      raise RecordingStudioApi::AuthorizationError, "Editing rate limits is not available for the current actor"
    end

    def rate_limit_params
      params.fetch(:rate_limit, {}).permit(
        :rate_limit_oauth_enabled,
        :rate_limit_oauth_requests,
        :rate_limit_oauth_period_seconds,
        :rate_limit_api_pre_auth_enabled,
        :rate_limit_api_pre_auth_requests,
        :rate_limit_api_pre_auth_period_seconds,
        :rate_limit_api_enabled,
        :rate_limit_api_read_requests,
        :rate_limit_api_read_period_seconds,
        :rate_limit_api_write_requests,
        :rate_limit_api_write_period_seconds
      ).to_h
    end

    def rate_limiting_redirect_path
      RecordingStudioApi.admin_rate_limiting_path(
        controller: self,
        **RecordingStudioApi::Admin::ApiContext.query_params(@current_admin_api.name),
        **page_nav_close_param
      )
    end

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
