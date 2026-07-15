# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"

class RotateApiCredentialTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    Current.actor = @user
    @root_recording, @access_recording = create_access_recording_for(user: @user)
    @payload = provision_api_client_for(access_recording: @access_recording, name: "Rotatable client")
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "rotates the credential and revokes the previous one" do
    previous_credential = @payload.fetch(:credential)

    result = RecordingStudioApi::Services::RotateApiCredential.call(
      api_client: @payload.fetch(:api_client),
      actor: @user
    )

    assert result.success?, result.error

    rotated_payload = result.value
    new_credential = rotated_payload.fetch(:credential)
    parsed_token = RecordingStudioApi::Token.parse(rotated_payload.fetch(:token))

    assert_equal previous_credential, rotated_payload.fetch(:previous_credential)
    assert_not_equal previous_credential.id, new_credential.id
    assert_not_nil previous_credential.reload.revoked_at
    assert_equal @payload.fetch(:api_client).id, new_credential.api_client_id
    assert_equal @payload.fetch(:api_client).recording.id, new_credential.recording.parent_recording_id
    assert_equal parsed_token.fetch(:public_id), new_credential.token_public_id
    assert_not_equal rotated_payload.fetch(:token), new_credential.token_digest
  end

  test "preserves the previous credential expiry by default" do
    expires_at = 3.days.from_now.change(usec: 0)
    @payload.fetch(:credential).update_columns(expires_at: expires_at, updated_at: Time.current)

    result = RecordingStudioApi::Services::RotateApiCredential.call(
      api_client: @payload.fetch(:api_client),
      actor: @user
    )

    assert result.success?, result.error
    assert_equal expires_at, result.value.fetch(:credential).expires_at
  end

  test "rejects rotation when the actor cannot manage the client access" do
    view_user = create_user(email: "rotate-view@example.com")

    result = RecordingStudioApi::Services::RotateApiCredential.call(
      api_client: @payload.fetch(:api_client),
      actor: view_user
    )

    assert result.failure?
    assert_equal "Actor is not authorized to manage API access for this recording", result.error
  end
end