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
    @client_access_recording = payload.fetch(:access_recording)
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
    assert_equal @client_access_recording.id, result.value.access_recording.id
    assert_equal @root_recording.id, result.value.root_recording.id
  end

  test "rejects a bearer token belonging to another api" do
    RecordingStudioApi.configuration.api(:operations)

    result = RecordingStudioApi::Services::AuthenticateOauthAccessToken.call(
      authorization_header: "Bearer #{@access_token}",
      api: :operations
    )

    assert result.failure?
    assert_equal "Bearer access token is invalid", result.error
    assert_nil @credential.reload.last_used_at
  end

  test "rejects malformed OAuth access tokens" do
    result = RecordingStudioApi::Services::AuthenticateOauthAccessToken.call(
      authorization_header: "Bearer rsapi_not_oauth_format"
    )

    assert result.failure?
    assert_equal "Bearer access token format is invalid", result.error
  end

  test "rejects inactive access tokens" do
    access_token = RecordingStudioApi::ApiAccessToken.find_by(
      token_digest: RecordingStudioApi::OauthAccessToken.digest(@access_token)
    )
    access_token.revoke!

    result = RecordingStudioApi::Services::AuthenticateOauthAccessToken.call(
      authorization_header: "Bearer #{@access_token}"
    )

    assert result.failure?
    assert_equal "Bearer access token is inactive", result.error
  end

  test "rejects access tokens after the parent credential expires" do
    @credential.update_columns(expires_at: 1.second.ago, updated_at: Time.current)

    result = RecordingStudioApi::Services::AuthenticateOauthAccessToken.call(
      authorization_header: "Bearer #{@access_token}"
    )

    assert result.failure?
    assert_equal "Bearer access token is inactive", result.error
  end

  test "rejects access tokens after the parent credential is revoked" do
    @credential.revoke!

    result = RecordingStudioApi::Services::AuthenticateOauthAccessToken.call(
      authorization_header: "Bearer #{@access_token}"
    )

    assert result.failure?
    assert_equal "Bearer access token is inactive", result.error
  end

  test "rejects an access token exactly at its expiry without updating usage timestamps" do
    access_token = RecordingStudioApi::ApiAccessToken.find_by!(
      token_digest: RecordingStudioApi::OauthAccessToken.digest(@access_token)
    )
    assert_nil access_token.last_used_at
    assert_nil @credential.last_used_at

    travel_to Time.zone.parse("2026-07-15 12:00:00 UTC") do
      access_token.update_columns(expires_at: Time.current, updated_at: Time.current)

      result = RecordingStudioApi::Services::AuthenticateOauthAccessToken.call(
        authorization_header: "Bearer #{@access_token}"
      )

      assert result.failure?
      assert_equal "Bearer access token is inactive", result.error
      assert_nil access_token.reload.last_used_at
      assert_nil @credential.reload.last_used_at
    end
  end

  test "rejects access tokens with trashed credential recordings" do
    @credential.recording.update_column(:trashed_at, Time.current)

    result = RecordingStudioApi::Services::AuthenticateOauthAccessToken.call(
      authorization_header: "Bearer #{@access_token}"
    )

    assert result.failure?
    assert_equal "Bearer access token is invalid", result.error
  end

  test "rejects access tokens when the effective access recording is trashed" do
    @client_access_recording.update_column(:trashed_at, Time.current)

    result = RecordingStudioApi::Services::AuthenticateOauthAccessToken.call(
      authorization_header: "Bearer #{@access_token}"
    )

    assert result.failure?
    assert_equal "Bearer access token is inactive", result.error
  end

  test "rejects access tokens when the API client recording is trashed" do
    @credential.api_client.recording.update_column(:trashed_at, Time.current)

    result = RecordingStudioApi::Services::AuthenticateOauthAccessToken.call(
      authorization_header: "Bearer #{@access_token}"
    )

    assert result.failure?
    assert_equal "Bearer access token is inactive", result.error
  end

  test "rejects access tokens when the root recording is trashed" do
    @root_recording.update_column(:trashed_at, Time.current)

    result = RecordingStudioApi::Services::AuthenticateOauthAccessToken.call(
      authorization_header: "Bearer #{@access_token}"
    )

    assert result.failure?
    assert_equal "Bearer access token scope is invalid", result.error
  end

  test "rejects access tokens with trashed token recordings" do
    access_token = RecordingStudioApi::ApiAccessToken.find_by(
      token_digest: RecordingStudioApi::OauthAccessToken.digest(@access_token)
    )
    access_token.recording.update_column(:trashed_at, Time.current)

    result = RecordingStudioApi::Services::AuthenticateOauthAccessToken.call(
      authorization_header: "Bearer #{@access_token}"
    )

    assert result.failure?
    assert_equal "Bearer access token is invalid", result.error
  end

  test "rejects access tokens missing token recordings" do
    access_token = RecordingStudioApi::ApiAccessToken.find_by(
      token_digest: RecordingStudioApi::OauthAccessToken.digest(@access_token)
    )
    access_token.recording.destroy!

    result = RecordingStudioApi::Services::AuthenticateOauthAccessToken.call(
      authorization_header: "Bearer #{@access_token}"
    )

    assert result.failure?
    assert_equal "Bearer access token is invalid", result.error
  end

  test "authenticates through registered token authenticator" do
    custom_token = RecordingStudioApi::OauthAccessToken.generate.fetch(:token)

    RecordingStudioApi.register_token_authenticator(
      lambda do |token:|
        next if token != custom_token

        { credential: @credential }
      end
    )

    result = RecordingStudioApi::Services::AuthenticateOauthAccessToken.call(
      authorization_header: "Bearer #{custom_token}"
    )

    assert result.success?, result.error
    assert_equal @credential.api_client_id, result.value.api_client.id
    assert_equal @credential.id, result.value.credential.id
    assert_equal @client_access_recording.id, result.value.access_recording.id
  end

  test "authenticates custom token format accepted by registered authenticator" do
    custom_token = "rsapp_at_#{SecureRandom.urlsafe_base64(32)}"
    credential = @credential

    authenticator = Class.new do
      define_method(:valid_format?) do |token|
        token.to_s.start_with?("rsapp_at_")
      end

      define_method(:call) do |token:|
        { credential: credential } if token == custom_token
      end
    end.new

    RecordingStudioApi.register_token_authenticator(authenticator)

    result = RecordingStudioApi::Services::AuthenticateOauthAccessToken.call(
      authorization_header: "Bearer #{custom_token}"
    )

    assert result.success?, result.error
    assert_equal @credential.api_client_id, result.value.api_client.id
    assert_equal @credential.id, result.value.credential.id
    assert_equal @client_access_recording.id, result.value.access_recording.id
  end

  test "rejects custom token format without registered format acceptance" do
    custom_token = "rsapp_at_#{SecureRandom.urlsafe_base64(32)}"

    RecordingStudioApi.register_token_authenticator(
      lambda do |token:|
        { credential: @credential } if token == custom_token
      end
    )

    result = RecordingStudioApi::Services::AuthenticateOauthAccessToken.call(
      authorization_header: "Bearer #{custom_token}"
    )

    assert result.failure?
    assert_equal "Bearer access token format is invalid", result.error
  end
end
