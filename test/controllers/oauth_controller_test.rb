# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"

class OauthControllerTest < ActionDispatch::IntegrationTest
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    _root_recording, @access_recording = create_access_recording_for(user: @user)
    @payload = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: @access_recording,
      name: "OAuth endpoint client"
    ).value
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "issues access token with valid client credentials" do
    post "/recording_studio_api/oauth/token", params: {
      grant_type: "client_credentials",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: @payload.fetch(:token)
    }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "Bearer", body.fetch("token_type")
    assert_match(/\Arsapi_at_/, body.fetch("access_token"))
  end

  test "returns oauth error for invalid client credentials" do
    post "/recording_studio_api/oauth/token", params: {
      grant_type: "client_credentials",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: "invalid"
    }

    assert_response :unauthorized
    body = JSON.parse(response.body)
    assert_equal "invalid_client", body.fetch("error")
  end
end
