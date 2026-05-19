# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"

class IssueOauthAccessTokenTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    _root_recording, @access_recording = create_access_recording_for(user: @user)
    @payload = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: @access_recording,
      name: "OAuth client"
    ).value
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "issues an access token for valid client credentials" do
    result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: @payload.fetch(:token)
    )

    assert result.success?, result.error
    assert_equal "Bearer", result.value.fetch(:token_type)
    assert_operator result.value.fetch(:expires_in), :>, 0
    assert_match(/\Arsapi_at_/, result.value.fetch(:access_token))
  end

  test "rejects unsupported grant types" do
    result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "password",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: @payload.fetch(:token)
    )

    assert result.failure?
    assert_equal "unsupported_grant_type", result.error.fetch(:error)
  end

  test "rejects invalid client credentials" do
    result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: "invalid"
    )

    assert result.failure?
    assert_equal "invalid_client", result.error.fetch(:error)
  end
end
