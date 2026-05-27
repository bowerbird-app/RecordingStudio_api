# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"
require "base64"
require "digest"

class ExchangeOauthAuthorizationCodeTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    user = create_user
    _root_recording, @access_recording = create_access_recording_for(user: user)

    @oauth_client = RecordingStudioApi::OauthClient.create!(
      name: "Mobile app",
      client_identifier: "mobile-app-exchange",
      redirect_uri: "myapp://oauth/callback"
    )

    @code_verifier = SecureRandom.urlsafe_base64(64, false).first(96)
    code_challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(@code_verifier), padding: false)

    authorize_result = RecordingStudioApi::Services::AuthorizeOauthClient.call(
      response_type: "code",
      client_id: @oauth_client.client_identifier,
      redirect_uri: @oauth_client.redirect_uri,
      code_challenge: code_challenge,
      code_challenge_method: "S256",
      access_recording_id: @access_recording.id,
      state: "exchange-state"
    )

    @authorization_code = authorize_result.value.fetch(:code)
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "exchanges authorization code for access and refresh tokens" do
    result = RecordingStudioApi::Services::ExchangeOauthAuthorizationCode.call(
      grant_type: "authorization_code",
      client_id: @oauth_client.client_identifier,
      code: @authorization_code,
      redirect_uri: @oauth_client.redirect_uri,
      code_verifier: @code_verifier
    )

    assert result.success?, result.error
    assert_match(/\Arsapi_at_/, result.value.fetch(:access_token))
    assert_match(/\Arsapi_rt_/, result.value.fetch(:refresh_token))

    session = RecordingStudioApi::OauthGrantSession.order(created_at: :desc).first
    assert_not_nil session
    assert_equal @access_recording.id, session.access_recording_id
    assert_not_nil session.recording
    assert_equal @access_recording.id, session.recording.parent_recording_id

    access_token = RecordingStudioApi::OauthSessionAccessToken.order(created_at: :desc).first
    assert_not_nil access_token
    assert_not_nil access_token.recording
    assert_equal session.recording.id, access_token.recording.parent_recording_id

    refresh_token = RecordingStudioApi::OauthRefreshToken.order(created_at: :desc).first
    assert_not_nil refresh_token
    assert_not_nil refresh_token.recording
    assert_equal session.recording.id, refresh_token.recording.parent_recording_id
  end

  test "rejects authorization code replay" do
    first_result = RecordingStudioApi::Services::ExchangeOauthAuthorizationCode.call(
      grant_type: "authorization_code",
      client_id: @oauth_client.client_identifier,
      code: @authorization_code,
      redirect_uri: @oauth_client.redirect_uri,
      code_verifier: @code_verifier
    )
    assert first_result.success?, first_result.error

    initial_session_count = RecordingStudioApi::OauthGrantSession.count
    initial_access_token_count = RecordingStudioApi::OauthSessionAccessToken.count
    initial_refresh_token_count = RecordingStudioApi::OauthRefreshToken.count

    replay_result = RecordingStudioApi::Services::ExchangeOauthAuthorizationCode.call(
      grant_type: "authorization_code",
      client_id: @oauth_client.client_identifier,
      code: @authorization_code,
      redirect_uri: @oauth_client.redirect_uri,
      code_verifier: @code_verifier
    )

    assert replay_result.failure?
    assert_equal "invalid_grant", replay_result.error.fetch(:error)
    assert_equal initial_session_count, RecordingStudioApi::OauthGrantSession.count
    assert_equal initial_access_token_count, RecordingStudioApi::OauthSessionAccessToken.count
    assert_equal initial_refresh_token_count, RecordingStudioApi::OauthRefreshToken.count
  end
end
