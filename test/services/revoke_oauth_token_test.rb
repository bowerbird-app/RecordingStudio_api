# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"
require "base64"
require "digest"

class RevokeOauthTokenTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    user = create_user
    _root_recording, @access_recording = create_access_recording_for(user: user)

    @oauth_client = RecordingStudioApi::OauthClient.create!(
      name: "Mobile app",
      client_identifier: "mobile-app-revoke",
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

    @access_token = exchange_result.value.fetch(:access_token)
    @refresh_token = exchange_result.value.fetch(:refresh_token)
    @session = RecordingStudioApi::OauthGrantSession.order(created_at: :desc).first
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "revokes session family by refresh token" do
    result = RecordingStudioApi::Services::RevokeOauthToken.call(
      client_id: @oauth_client.client_identifier,
      token: @refresh_token,
      token_type_hint: "refresh_token"
    )

    assert result.success?, result.error
    assert_not_nil @session.reload.revoked_at
    assert_equal 0, RecordingStudioApi::OauthSessionAccessToken.active.where(oauth_grant_session_id: @session.id).count
    assert_equal 0, RecordingStudioApi::OauthRefreshToken.active.where(oauth_grant_session_id: @session.id).count
  end

  test "returns success for unknown token" do
    result = RecordingStudioApi::Services::RevokeOauthToken.call(
      client_id: @oauth_client.client_identifier,
      token: "rsapi_rt_unknown",
      token_type_hint: "refresh_token"
    )

    assert result.success?, result.error
    assert_nil @session.reload.revoked_at
  end
end
