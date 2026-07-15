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
    assert_in_delta 1.hour.to_i, result.value.fetch(:expires_in), 2
    assert_match(/\Arsapi_at_/, result.value.fetch(:access_token))

    access_token = RecordingStudioApi::ApiAccessToken.order(created_at: :desc).first
    assert_not_nil access_token
    assert_not_nil access_token.recording
    assert_equal @payload.fetch(:credential).recording&.id, access_token.recording.parent_recording_id
  end

  test "uses configured access token ttl for bearer token expiry" do
    travel_to Time.zone.parse("2026-05-18 12:00:00 UTC") do
      RecordingStudioApi.configuration.access_token_ttl = 15.minutes

      result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
        grant_type: "client_credentials",
        client_id: @payload.fetch(:credential).oauth_client_id,
        client_secret: @payload.fetch(:token)
      )

      assert result.success?, result.error
      assert_in_delta 15.minutes.to_i, result.value.fetch(:expires_in), 2

      access_token = RecordingStudioApi::ApiAccessToken.find_by!(
        token_digest: RecordingStudioApi::OauthAccessToken.digest(result.value.fetch(:access_token))
      )
      assert_equal 15.minutes.from_now, access_token.expires_at
    end
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

  test "does not issue an access token for an expired credential" do
    @payload.fetch(:credential).update_columns(expires_at: 1.second.ago, updated_at: Time.current)

    result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: @payload.fetch(:token)
    )

    assert result.failure?
    assert_equal "invalid_client", result.error.fetch(:error)
  end

  test "does not issue an access token for a revoked credential" do
    @payload.fetch(:credential).revoke!

    result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: @payload.fetch(:token)
    )

    assert result.failure?
    assert_equal "invalid_client", result.error.fetch(:error)
  end

  test "does not expose database errors during token issuance" do
    result = RecordingStudioApi::ApiAccessToken.stub(:create!, lambda { |**|
      raise ActiveRecord::StatementInvalid, "database constraint detail"
    }) do
      RecordingStudioApi::Services::IssueOauthAccessToken.call(
        grant_type: "client_credentials",
        client_id: @payload.fetch(:credential).oauth_client_id,
        client_secret: @payload.fetch(:token)
      )
    end

    assert result.failure?
    assert_equal "server_error", result.error.fetch(:error)
    assert_equal RecordingStudioApi::OauthErrorMapper::SERVER_ERROR_DESCRIPTION, result.error.fetch(:error_description)
    assert_not_includes result.error.fetch(:error_description), "database constraint detail"
  end
end
