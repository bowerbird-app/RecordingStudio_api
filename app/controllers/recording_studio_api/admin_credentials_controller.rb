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

    def load_credential
      scope = RecordingStudioApi::ApiCredential
              .joins(:api_client)
              .where(api_client: { api_key: @current_admin_api.name })

      root_recording = current_root_recording
      if root_recording.present?
        recordings = RecordingStudio::Recording.arel_table
        scope = scope.joins(api_client: :access_recording).where(
          recordings[:root_recording_id].eq(root_recording.id).or(recordings[:id].eq(root_recording.id))
        )
      end

      @credential = scope.find(params[:id])
    end
  end
end