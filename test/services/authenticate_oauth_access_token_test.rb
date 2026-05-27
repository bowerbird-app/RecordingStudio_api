# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"
require "base64"
require "digest"

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

  test "authenticates mobile oauth session access token" do
    oauth_client = RecordingStudioApi::OauthClient.create!(
      name: "Mobile app",
      client_identifier: "mobile-auth-client",
      redirect_uri: "myapp://oauth/callback"
    )

    code_verifier = SecureRandom.urlsafe_base64(64, false).first(96)
    code_challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false)

    authorize_result = RecordingStudioApi::Services::AuthorizeOauthClient.call(
      response_type: "code",
      client_id: oauth_client.client_identifier,
      redirect_uri: oauth_client.redirect_uri,
      code_challenge: code_challenge,
      code_challenge_method: "S256",
      access_recording_id: @access_recording.id
    )

    exchange_result = RecordingStudioApi::Services::ExchangeOauthAuthorizationCode.call(
      grant_type: "authorization_code",
      client_id: oauth_client.client_identifier,
      code: authorize_result.value.fetch(:code),
      redirect_uri: oauth_client.redirect_uri,
      code_verifier: code_verifier
    )

    mobile_token = exchange_result.value.fetch(:access_token)

    result = RecordingStudioApi::Services::AuthenticateOauthAccessToken.call(
      authorization_header: "Bearer #{mobile_token}"
    )

    assert result.success?, result.error
    assert_equal oauth_client.id, result.value.api_client.id
    assert_equal @access_recording.id, result.value.access_recording.id
    assert_not_nil result.value.credential
    assert_instance_of RecordingStudioApi::OauthGrantSession, result.value.credential
  end
end
