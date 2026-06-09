# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"

class AuthenticateBearerTokenTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user)
    @payload = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: @access_recording,
      name: "Primary token"
    ).value
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "authenticates a valid bearer token" do
    result = RecordingStudioApi::Services::AuthenticateBearerToken.call(
      authorization_header: "Bearer #{@payload.fetch(:token)}"
    )

    assert result.success?, result.error
    assert_equal @payload.fetch(:api_client).id, result.value.api_client.id
    assert_equal @payload.fetch(:credential).id, result.value.credential.id
    assert_equal @payload.fetch(:access_recording).id, result.value.access_recording.id
    assert_equal @root_recording.id, result.value.root_recording.id
  end

  test "rejects a revoked bearer token" do
    @payload.fetch(:credential).revoke!

    result = RecordingStudioApi::Services::AuthenticateBearerToken.call(
      authorization_header: "Bearer #{@payload.fetch(:token)}"
    )

    assert result.failure?
    assert_equal "Bearer token is inactive", result.error
  end

  test "rejects a token when its root recording is trashed" do
    user = create_user(email: "scoped-auth@example.com")
    root_recording, access_recording = create_access_recording_for(user: user)
    payload = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: access_recording,
      name: "Scoped token"
    ).value

    root_recording.update!(trashed_at: Time.current)

    result = RecordingStudioApi::Services::AuthenticateBearerToken.call(
      authorization_header: "Bearer #{payload.fetch(:token)}"
    )

    assert result.failure?
    assert_equal "Bearer token scope is invalid", result.error
  end
end
