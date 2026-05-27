# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"
require "devise/test/integration_helpers"
require "uri"
require "cgi"
require "base64"
require "digest"

class OauthControllerTest < ActionDispatch::IntegrationTest
  include ApiDummyHelpers
  include Devise::Test::IntegrationHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    _root_recording, @access_recording = create_access_recording_for(user: @user)
    sign_in @user
    @payload = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: @access_recording,
      name: "OAuth endpoint client"
    ).value
  end

  teardown do
    RecordingStudioApi::Concerns::RateLimiting.decider = nil
    RecordingStudioApi::Concerns::RequestLogging.writer = nil
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "returns too many requests when oauth endpoint is rate limited" do
    RecordingStudioApi.configuration.rate_limit_oauth_enabled = true
    RecordingStudioApi::Concerns::RateLimiting.decider = lambda {
      {
        limited: true,
        limit: 1,
        remaining: 0,
        retry_after: 42
      }
    }

    post "/recording_studio_api/oauth/token", params: {
      grant_type: "client_credentials",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: @payload.fetch(:token)
    }

    assert_response :too_many_requests
    assert_equal "42", response.headers["Retry-After"]
    assert_equal "1", response.headers["X-RateLimit-Limit"]
    assert_equal "0", response.headers["X-RateLimit-Remaining"]

    body = JSON.parse(response.body)
    assert_equal "rate_limit_exceeded", body.fetch("error")
  end

  test "writes oauth request log payload when request logging is enabled" do
    RecordingStudioApi.configuration.api_request_logging_enabled = true
    logged_payloads = []
    RecordingStudioApi::Concerns::RequestLogging.writer = lambda do |payload|
      logged_payloads << payload
    end

    post "/recording_studio_api/oauth/token", params: {
      grant_type: "client_credentials",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: "bad-secret"
    }

    assert_response :unauthorized
    assert_equal 1, logged_payloads.length

    payload = logged_payloads.first
    assert_equal "POST", payload.fetch(:request_method)
    assert_equal "/recording_studio_api/oauth/token", payload.fetch(:request_path)
    assert_equal 401, payload.fetch(:status_code)
    assert_equal "[FILTERED]", payload.fetch(:request_params).fetch("client_secret")
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

  test "falls back to client credentials flow for unsupported grant type" do
    post "/recording_studio_api/oauth/token", params: {
      grant_type: "custom_grant",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: @payload.fetch(:token)
    }

    assert_response :bad_request
    body = JSON.parse(response.body)
    assert_equal "unsupported_grant_type", body.fetch("error")
  end

  test "authorizes public oauth client with pkce and redirects with code" do
    oauth_client = RecordingStudioApi::OauthClient.create!(
      name: "Mobile app",
      client_identifier: "mobile-app-1",
      redirect_uri: "myapp://oauth/callback"
    )

    get "/recording_studio_api/oauth/authorize", params: {
      response_type: "code",
      client_id: oauth_client.client_identifier,
      redirect_uri: oauth_client.redirect_uri,
      code_challenge: "z7Qv8FnT9C1qT6fM2f0fQf5K5pCtjHCM8Uo-UNfQ2Q4",
      code_challenge_method: "S256",
      access_recording_id: @access_recording.id,
      state: "abc123"
    }

    assert_response :redirect
    location = response.headers.fetch("Location")
    uri = URI.parse(location)
    query = CGI.parse(uri.query.to_s)

    assert_equal oauth_client.redirect_uri, "#{uri.scheme}://#{uri.host}#{uri.path}"
    assert_not_nil query["code"]&.first
    assert_equal "abc123", query["state"]&.first

    created = RecordingStudioApi::OauthAuthorizationCode.order(created_at: :desc).first
    assert_not_nil created
    assert_not_nil created.recording
    assert_equal @access_recording.id, created.recording.parent_recording_id
  end

  test "returns oauth error when authorize request is invalid" do
    get "/recording_studio_api/oauth/authorize", params: {
      response_type: "token",
      client_id: "missing",
      redirect_uri: "myapp://oauth/callback",
      code_challenge: "abc",
      code_challenge_method: "plain",
      access_recording_id: @access_recording.id
    }

    assert_response :bad_request
    body = JSON.parse(response.body)
    assert_equal "unsupported_response_type", body.fetch("error")
  end

  test "requires authentication for authorize" do
    sign_out @user
    oauth_client = RecordingStudioApi::OauthClient.create!(
      name: "Mobile app",
      client_identifier: "mobile-app-auth-check",
      redirect_uri: "myapp://oauth/callback"
    )

    get "/recording_studio_api/oauth/authorize", params: {
      response_type: "code",
      client_id: oauth_client.client_identifier,
      redirect_uri: oauth_client.redirect_uri,
      code_challenge: "z7Qv8FnT9C1qT6fM2f0fQf5K5pCtjHCM8Uo-UNfQ2Q4",
      code_challenge_method: "S256",
      access_recording_id: @access_recording.id
    }

    assert_response :redirect
  end

  test "rejects authorize request for an access recording not owned by actor" do
    outsider = create_user(email: "outsider-authz@example.com")
    _outsider_root, outsider_access = create_access_recording_for(user: outsider)
    Current.actor = @user

    oauth_client = RecordingStudioApi::OauthClient.create!(
      name: "Mobile app",
      client_identifier: "mobile-app-owned-access",
      redirect_uri: "myapp://oauth/callback"
    )

    get "/recording_studio_api/oauth/authorize", params: {
      response_type: "code",
      client_id: oauth_client.client_identifier,
      redirect_uri: oauth_client.redirect_uri,
      code_challenge: "z7Qv8FnT9C1qT6fM2f0fQf5K5pCtjHCM8Uo-UNfQ2Q4",
      code_challenge_method: "S256",
      access_recording_id: outsider_access.id
    }

    assert_response :bad_request
    body = JSON.parse(response.body)
    assert_equal "invalid_scope", body.fetch("error")
  end

  test "auto-selects access recording when actor has exactly one" do
    oauth_client = RecordingStudioApi::OauthClient.create!(
      name: "Mobile app",
      client_identifier: "mobile-app-auto-access",
      redirect_uri: "myapp://oauth/callback"
    )

    get "/recording_studio_api/oauth/authorize", params: {
      response_type: "code",
      client_id: oauth_client.client_identifier,
      redirect_uri: oauth_client.redirect_uri,
      code_challenge: "z7Qv8FnT9C1qT6fM2f0fQf5K5pCtjHCM8Uo-UNfQ2Q4",
      code_challenge_method: "S256"
    }

    assert_response :redirect
    created = RecordingStudioApi::OauthAuthorizationCode.order(created_at: :desc).first
    assert_equal @access_recording.id, created.access_recording_id
  end

  test "returns invalid scope when actor has no access recordings" do
    sign_out @user
    user_without_access = create_user(email: "no-access-authz@example.com")
    sign_in user_without_access

    oauth_client = RecordingStudioApi::OauthClient.create!(
      name: "Mobile app",
      client_identifier: "mobile-app-no-access",
      redirect_uri: "myapp://oauth/callback"
    )

    get "/recording_studio_api/oauth/authorize", params: {
      response_type: "code",
      client_id: oauth_client.client_identifier,
      redirect_uri: oauth_client.redirect_uri,
      code_challenge: "z7Qv8FnT9C1qT6fM2f0fQf5K5pCtjHCM8Uo-UNfQ2Q4",
      code_challenge_method: "S256"
    }

    assert_response :bad_request
    body = JSON.parse(response.body)
    assert_equal "invalid_scope", body.fetch("error")
  end

  test "renders access selection page when actor has multiple access recordings" do
    _other_root, _other_access = create_access_recording_for(user: @user)

    oauth_client = RecordingStudioApi::OauthClient.create!(
      name: "Mobile app",
      client_identifier: "mobile-app-multi-access",
      redirect_uri: "myapp://oauth/callback"
    )

    get "/recording_studio_api/oauth/authorize", params: {
      response_type: "code",
      client_id: oauth_client.client_identifier,
      redirect_uri: oauth_client.redirect_uri,
      code_challenge: "z7Qv8FnT9C1qT6fM2f0fQf5K5pCtjHCM8Uo-UNfQ2Q4",
      code_challenge_method: "S256"
    }

    assert_response :success
    assert_includes response.body, "Choose access"
    assert_includes response.body, "Continue"
  end

  test "exchanges authorization code for access and refresh tokens" do
    oauth_client = RecordingStudioApi::OauthClient.create!(
      name: "Mobile app",
      client_identifier: "mobile-app-controller",
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

    post "/recording_studio_api/oauth/token", params: {
      grant_type: "authorization_code",
      client_id: oauth_client.client_identifier,
      code: authorize_result.value.fetch(:code),
      redirect_uri: oauth_client.redirect_uri,
      code_verifier: code_verifier
    }

    assert_response :success
    body = JSON.parse(response.body)
    assert_match(/\Arsapi_at_/, body.fetch("access_token"))
    assert_match(/\Arsapi_rt_/, body.fetch("refresh_token"))
  end

  test "refreshes mobile access token" do
    oauth_client = RecordingStudioApi::OauthClient.create!(
      name: "Mobile app",
      client_identifier: "mobile-app-refresh-controller",
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

    post "/recording_studio_api/oauth/token", params: {
      grant_type: "refresh_token",
      client_id: oauth_client.client_identifier,
      refresh_token: exchange_result.value.fetch(:refresh_token)
    }

    assert_response :success
    body = JSON.parse(response.body)
    assert_match(/\Arsapi_at_/, body.fetch("access_token"))
    assert_match(/\Arsapi_rt_/, body.fetch("refresh_token"))
  end

  test "revokes mobile session by refresh token" do
    oauth_client = RecordingStudioApi::OauthClient.create!(
      name: "Mobile app",
      client_identifier: "mobile-app-revoke-controller",
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

    post "/recording_studio_api/oauth/revoke", params: {
      client_id: oauth_client.client_identifier,
      token: exchange_result.value.fetch(:refresh_token),
      token_type_hint: "refresh_token"
    }

    assert_response :success

    session = RecordingStudioApi::OauthGrantSession.order(created_at: :desc).first
    assert_not_nil session.reload.revoked_at
  end

  test "allows session owner revoke by oauth_grant_session_id with bearer token" do
    oauth_client = RecordingStudioApi::OauthClient.create!(
      name: "Mobile app",
      client_identifier: "mobile-app-session-revoke-controller",
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

    session = RecordingStudioApi::OauthGrantSession.order(created_at: :desc).first

    post "/recording_studio_api/oauth/revoke",
         params: { oauth_grant_session_id: session.id },
         headers: { "Authorization" => "Bearer #{exchange_result.value.fetch(:access_token)}" }

    assert_response :success
    assert_not_nil session.reload.revoked_at
  end

  test "returns oauth error when revoke client is invalid" do
    post "/recording_studio_api/oauth/revoke", params: {
      client_id: "unknown-client",
      token: "rsapi_at_invalid",
      token_type_hint: "access_token"
    }

    assert_response :unauthorized
    body = JSON.parse(response.body)
    assert_equal "invalid_client", body.fetch("error")
  end
end
