# frozen_string_literal: true

module PublicApi
class ScalarTestCredentialsController < ApplicationController
  include PublicApi::ScalarTestAuth

  layout "recording_studio/default_layout"

  prepend_before_action :authorize_scalar_test_auth!
  before_action :load_scalar_test_auth, only: :show

  def show
  end

  def create
    recording = selected_scalar_test_auth_recording
    return redirect_with_scalar_test_auth_error("Choose an API access point first.") if recording.nil?
    return redirect_with_scalar_test_auth_error("Choose a valid access role.") unless scalar_test_auth_roles.include?(params[:role].to_s)

    revoke_scalar_test_auth_session!
    result = RecordingStudioApi::Services::IssueTestCredential.call(
      api: scalar_test_auth_api,
      actor: scalar_test_auth_actor,
      access_point_recording: recording,
      role: params[:role],
      name: "API #{params[:role]} test token"
    )
    return redirect_with_scalar_test_auth_error(result.error) if result.failure?

    session[scalar_test_auth_session_key] = scalar_test_auth_session_payload(result.value)
    session[scalar_test_auth_notice_key] = "API test bearer token issued."
    redirect_to scalar_test_auth_return_path
  end

  def destroy
    revoke_scalar_test_auth_session!
    session.delete(scalar_test_auth_session_key)
    session[scalar_test_auth_notice_key] = "API test bearer token revoked."
    redirect_to scalar_test_auth_return_path
  end

  private

  def authorize_scalar_test_auth!
    return head :not_found unless scalar_test_auth_enabled?
    return head :unauthorized if scalar_test_auth_actor.blank?

    head :forbidden if scalar_test_auth_access_points.empty?
  end

  def selected_scalar_test_auth_recording
    recording_id = params[:access_point_recording_id].presence
    return if recording_id.blank?

    RecordingStudio::Recording.unscoped
      .includes(:recordable)
      .where(recordable_type: RecordingStudioApi.api_recordable_types(api: scalar_test_auth_api))
      .find_by(id: recording_id, trashed_at: nil)
  end

  def revoke_scalar_test_auth_session!
    state = session[scalar_test_auth_session_key] || {}
    return if state["credential_id"].blank? || state["access_token_id"].blank?

    RecordingStudioApi::Services::RevokeTestCredential.call(
      api: scalar_test_auth_api,
      credential_id: state["credential_id"],
      access_token_id: state["access_token_id"]
    )
  end

  def redirect_with_scalar_test_auth_error(message)
    session[scalar_test_auth_error_key] = message.to_s
    redirect_to scalar_test_auth_return_path
  end
end
end
