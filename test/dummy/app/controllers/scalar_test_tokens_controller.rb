# frozen_string_literal: true

class ScalarTestTokensController < ApplicationController
  SESSION_KEY = "scalar_test_token"
  ROLE_OPTIONS = %w[view edit admin].freeze

  def create
    access_point_recording = selected_access_point_recording
    role = params[:role].to_s

    return redirect_with_error("Choose an API access point first.") if access_point_recording.nil?
    return redirect_with_error("Choose a valid access role.") unless ROLE_OPTIONS.include?(role)
    return redirect_with_error("You need admin access to issue a Scalar test token for this branch.") unless can_manage_access_point?(access_point_recording)

    revoke_session_token!
    session[SESSION_KEY] = issue_test_token!(access_point_recording: access_point_recording, role: role)
    session["scalar_test_token_notice"] = "Scalar test bearer token issued."
    redirect_to docs_scalar_path(anchor: "scalar-test-auth")
  rescue ActiveRecord::ActiveRecordError, RecordingStudioApi::Error => error
    redirect_with_error(error.message)
  end

  def destroy
    revoke_session_token!
    session.delete(SESSION_KEY)
    session["scalar_test_token_notice"] = "Scalar test bearer token revoked."
    redirect_to docs_scalar_path(anchor: "scalar-test-auth")
  end

  private

  def selected_access_point_recording
    recording_id = params[:access_point_recording_id].presence
    return if recording_id.blank?

    RecordingStudio::Recording.unscoped.includes(:recordable).find_by(id: recording_id, trashed_at: nil)
  end

  def can_manage_access_point?(recording)
    access_management_policy.can_manage_root_recording?(root_recording_for(recording))
  end

  def access_management_policy
    @access_management_policy ||= RecordingStudioApi::AccessManagementPolicy.new(actor: current_user)
  end

  def issue_test_token!(access_point_recording:, role:)
    issued_payload = nil

    ActiveRecord::Base.transaction do
      access_recording = create_access_recording!(access_point_recording: access_point_recording, role: role)
      provision_result = RecordingStudioApi::Services::ProvisionApiClient.call(
        access_recording: access_recording,
        name: "Scalar #{role} test token"
      )
      raise RecordingStudioApi::Error, provision_result.error if provision_result.failure?

      credential = provision_result.value.fetch(:credential)
      issue_result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
        grant_type: "client_credentials",
        client_id: credential.oauth_client_id,
        client_secret: provision_result.value.fetch(:token)
      )
      raise RecordingStudioApi::Error, oauth_error_message(issue_result.error) if issue_result.failure?

      access_token = issue_result.value.fetch(:access_token)
      access_token_record = RecordingStudioApi::ApiAccessToken.find_by!(
        token_digest: RecordingStudioApi::OauthAccessToken.digest(access_token)
      )

      issued_payload = session_payload_for(
        access_point_recording: access_point_recording,
        access_recording: access_recording,
        credential: credential,
        access_token_record: access_token_record,
        access_token: access_token,
        role: role
      )
    end

    issued_payload
  end

  def create_access_recording!(access_point_recording:, role:)
    access = RecordingStudio::Access.create!(actor: current_user, role: role)

    RecordingStudio.record!(
      action: "created",
      recordable: access,
      root_recording: root_recording_for(access_point_recording),
      parent_recording: access_point_recording,
      actor: current_user
    ).recording
  end

  def session_payload_for(access_point_recording:, access_recording:, credential:, access_token_record:, access_token:, role:)
    root_recording = root_recording_for(access_point_recording)

    {
      "access_token" => access_token,
      "access_token_id" => access_token_record.id,
      "api_client_id" => credential.api_client_id,
      "credential_id" => credential.id,
      "client_id" => credential.oauth_client_id,
      "role" => role,
      "scope_recording_id" => access_point_recording.id,
      "scope_label" => recording_label(access_point_recording),
      "root_recording_id" => root_recording.id,
      "root_label" => recording_label(root_recording),
      "access_recording_id" => access_recording.id,
      "expires_at" => access_token_record.expires_at&.iso8601,
      "issued_at" => Time.current.iso8601
    }
  end

  def revoke_session_token!
    token_state = session[SESSION_KEY] || {}
    token = RecordingStudioApi::ApiAccessToken.find_by(id: token_state["access_token_id"])
    credential = RecordingStudioApi::ApiCredential.find_by(id: token_state["credential_id"])

    token&.revoke!
    credential&.revoke!
  end

  def root_recording_for(recording)
    recording.root_recording || recording
  end

  def recording_label(recording)
    type_label = recording.recordable_type.to_s.demodulize.underscore.humanize
    identifier = recordable_identifier(recording.recordable)

    "#{type_label}: #{identifier}"
  end

  def recordable_identifier(recordable)
    return "Unknown recordable" if recordable.nil?

    %i[name title email label slug identifier].each do |attribute|
      next unless recordable.respond_to?(attribute)

      value = recordable.public_send(attribute)
      return value if value.present?
    end

    actor = recordable.actor if recordable.respond_to?(:actor)
    actor_email = actor.email if actor&.respond_to?(:email) && actor.email.present?

    if recordable.respond_to?(:role) && recordable.role.present? && actor_email.present?
      return "#{recordable.role.to_s.humanize} for #{actor_email}"
    end

    return recordable.role.to_s.humanize if recordable.respond_to?(:role) && recordable.role.present?

    "##{recordable.id}"
  end

  def oauth_error_message(error)
    return error.to_s unless error.is_a?(Hash)

    [ error[:error], error[:error_description] ].compact.join(": ")
  end

  def redirect_with_error(message)
    session["scalar_test_token_error"] = message
    redirect_to docs_scalar_path(anchor: "scalar-test-auth")
  end
end
