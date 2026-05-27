# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"
require "base64"
require "digest"

class RefreshOauthAccessTokenTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    user = create_user
    _root_recording, @access_recording = create_access_recording_for(user: user)

    @oauth_client = RecordingStudioApi::OauthClient.create!(
      name: "Mobile app",
      client_identifier: "mobile-app-refresh",
      redirect_uri: "myapp://oauth/callback"
    )

    code_verifier = SecureRandom.urlsafe_base64(64, false).first(96)
    code_challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false)

    authorize_result = RecordingStudioApi::Services::AuthorizeOauthClient.call(
      response_type: "code",
      client_id: @oauth_client.client_identifier,
      redirect_uri: @oauth_client.redirect_uri,
      code_challenge: code_challenge,
      code_challenge_method: "S256",
      access_recording_id: @access_recording.id
    )

    exchange_result = RecordingStudioApi::Services::ExchangeOauthAuthorizationCode.call(
      grant_type: "authorization_code",
      client_id: @oauth_client.client_identifier,
      code: authorize_result.value.fetch(:code),
      redirect_uri: @oauth_client.redirect_uri,
      code_verifier: code_verifier
    )

    @refresh_token = exchange_result.value.fetch(:refresh_token)
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "rotates refresh token and issues a new access token" do
    original_refresh = RecordingStudioApi::OauthRefreshToken.find_by(
      token_digest: RecordingStudioApi::OauthRefreshTokenValue.digest(@refresh_token)
    )
    assert_not_nil original_refresh

    result = RecordingStudioApi::Services::RefreshOauthAccessToken.call(
      grant_type: "refresh_token",
      client_id: @oauth_client.client_identifier,
      refresh_token: @refresh_token
    )

    assert result.success?, result.error
    assert_match(/\Arsapi_at_/, result.value.fetch(:access_token))
    assert_match(/\Arsapi_rt_/, result.value.fetch(:refresh_token))

    rotated = RecordingStudioApi::OauthRefreshToken.find_by(
      token_digest: RecordingStudioApi::OauthRefreshTokenValue.digest(result.value.fetch(:refresh_token))
    )
    assert_not_nil rotated

    original_refresh.reload
    assert_not_nil original_refresh.consumed_at
    assert_equal rotated.id, original_refresh.replaced_by_id
  end

  test "revokes grant session when used refresh token is replayed" do
    first_result = RecordingStudioApi::Services::RefreshOauthAccessToken.call(
      grant_type: "refresh_token",
      client_id: @oauth_client.client_identifier,
      refresh_token: @refresh_token
    )
    assert first_result.success?, first_result.error

    initial_access_token_count = RecordingStudioApi::OauthSessionAccessToken.count
    initial_refresh_token_count = RecordingStudioApi::OauthRefreshToken.count

    replay_result = RecordingStudioApi::Services::RefreshOauthAccessToken.call(
      grant_type: "refresh_token",
      client_id: @oauth_client.client_identifier,
      refresh_token: @refresh_token
    )

    assert replay_result.failure?
    assert_equal "invalid_grant", replay_result.error.fetch(:error)
    assert_equal initial_access_token_count, RecordingStudioApi::OauthSessionAccessToken.count
    assert_equal initial_refresh_token_count, RecordingStudioApi::OauthRefreshToken.count

    session = RecordingStudioApi::OauthGrantSession.order(created_at: :desc).first
    assert_not_nil session.revoked_at
  end
end
