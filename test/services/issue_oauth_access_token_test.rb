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

  test "rejects credentials belonging to another api" do
    RecordingStudioApi.configuration.api(:operations)

    result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: @payload.fetch(:token),
      api: :operations
    )

    assert result.failure?
    assert_equal "invalid_client", result.error.fetch(:error)
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

  test "rejects unknown grant types" do
    result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "password",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: @payload.fetch(:token)
    )

    assert result.failure?
    assert_equal "invalid_grant", result.error.fetch(:error)
  end

  test "rejects authorization_code when no grant handler is registered" do
    result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "authorization_code",
      client_id: "any-client",
      client_secret: "any-secret",
      params: { "code" => "abc" }
    )

    assert result.failure?
    assert_equal "invalid_grant", result.error.fetch(:error)
  end

  test "exchanges a registered grant type through the token service" do
    captured = nil
    RecordingStudioApi.register_oauth_grant(
      "authorization_code",
      handler: lambda do |**kwargs|
        captured = kwargs
        RecordingStudioApi::Services::BaseService::Result.new(
          success: true,
          value: {
            access_token: "rsapi_at_double",
            token_type: "Bearer",
            expires_in: 3600
          }
        )
      end
    )

    result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "authorization_code",
      client_id: "oauth-client",
      client_secret: "oauth-secret",
      api: :public,
      params: { "code" => "abc", "grant_type" => "authorization_code" }
    )

    assert result.success?, result.error
    assert_equal "rsapi_at_double", result.value.fetch(:access_token)
    assert_equal "authorization_code", captured.fetch(:grant_type)
    assert_equal "abc", captured.fetch(:params).fetch("code")
    assert_equal "oauth-client", captured.fetch(:client_id)
    assert_equal "public", captured.fetch(:api)
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

  test "rejects unknown client_id with the same invalid_client error" do
    result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: "does-not-exist",
      client_secret: "any-secret"
    )

    assert result.failure?
    assert_equal "invalid_client", result.error.fetch(:error)
    assert_equal "client authentication failed", result.error.fetch(:error_description)
  end

  test "does not issue an access token for an expired credential" do
    issued = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: @payload.fetch(:token)
    )
    assert issued.success?, issued.error
    access_token = RecordingStudioApi::ApiAccessToken.find_by!(
      token_digest: RecordingStudioApi::OauthAccessToken.digest(issued.value.fetch(:access_token))
    )

    @payload.fetch(:credential).update_columns(expires_at: 1.second.ago, updated_at: Time.current)

    result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: @payload.fetch(:token)
    )

    assert result.failure?
    assert_equal "invalid_client", result.error.fetch(:error)
    assert_not_nil access_token.reload.revoked_at
    assert_nil @payload.fetch(:credential).reload.revoked_at
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

  test "revoking a credential also revokes its outstanding access tokens" do
    issued = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: @payload.fetch(:token)
    )
    assert issued.success?, issued.error

    access_token = RecordingStudioApi::ApiAccessToken.find_by!(
      token_digest: RecordingStudioApi::OauthAccessToken.digest(issued.value.fetch(:access_token))
    )
    assert_nil access_token.revoked_at

    @payload.fetch(:credential).revoke!

    assert_not_nil @payload.fetch(:credential).reload.revoked_at
    assert_not_nil access_token.reload.revoked_at
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
