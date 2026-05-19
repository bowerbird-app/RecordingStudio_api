# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"

class AuthenticateOauthAccessTokenTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user)
    payload = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: @access_recording,
      name: "OAuth auth client"
    ).value

    token_result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: payload.fetch(:credential).oauth_client_id,
      client_secret: payload.fetch(:token)
    )

    @access_token = token_result.value.fetch(:access_token)
    @credential = payload.fetch(:credential)
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "authenticates a valid OAuth bearer access token" do
    result = RecordingStudioApi::Services::AuthenticateOauthAccessToken.call(
      authorization_header: "Bearer #{@access_token}"
    )

    assert result.success?, result.error
    assert_equal @credential.api_client_id, result.value.api_client.id
    assert_equal @credential.id, result.value.credential.id
    assert_equal @access_recording.id, result.value.access_recording.id
    assert_equal @root_recording.id, result.value.root_recording.id
  end

  test "rejects malformed OAuth access tokens" do
    result = RecordingStudioApi::Services::AuthenticateOauthAccessToken.call(
      authorization_header: "Bearer rsapi_not_oauth_format"
    )

    assert result.failure?
    assert_equal "Bearer access token format is invalid", result.error
  end

  test "rejects inactive access tokens" do
    access_token = RecordingStudioApi::ApiAccessToken.last
    access_token.revoke!

    result = RecordingStudioApi::Services::AuthenticateOauthAccessToken.call(
      authorization_header: "Bearer #{@access_token}"
    )

    assert result.failure?
    assert_equal "Bearer access token is inactive", result.error
  end
end
