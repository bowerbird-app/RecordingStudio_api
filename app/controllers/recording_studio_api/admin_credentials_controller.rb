# frozen_string_literal: true

module RecordingStudioApi
  class AdminCredentialsController < AdminController
    before_action :authorize_admin_api_management!
    before_action :load_credential

    def revoke
      @credential.revoke! if @credential.revoked_at.nil?

      redirect_to page_nav_close_url, notice: "API credential revoked."
    end

    private

    def authorize_admin_api_management!
      return if RecordingStudioAccessible.authorized?(
        actor: current_request_actor,
        recording: @admin_api_recording,
        role: RecordingStudioApi.configuration.access_management_edit_role
      )

      raise RecordingStudioApi::AuthorizationError, "API credential management requires higher access"
    end

    # Match AdminApiCredentialsQuery: scope by named API. AdminController already
    # requires AdminRoot, so filtering by current_root_recording would 404 all
    # workspace-rooted credentials shown on the admin credentials screen.
    # Intentional: AdminRoot operators manage credentials across the named API,
    # not only under the currently selected workspace root.
    def load_credential
      @credential = RecordingStudioApi::ApiCredential
                    .joins(:api_client)
                    .where(api_client: { api_key: @current_admin_api.name })
                    .find(params[:id])
    end
  end
end
