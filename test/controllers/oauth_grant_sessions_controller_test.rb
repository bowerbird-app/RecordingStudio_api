# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"
require "devise/test/integration_helpers"
require "base64"
require "digest"

class OauthGrantSessionsControllerTest < ActionDispatch::IntegrationTest
  include ApiDummyHelpers
  include Devise::Test::IntegrationHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!

    @user = create_user(email: "oauth-sessions@example.com")
    sign_in @user

    _root_recording, @access_recording = create_access_recording_for(user: @user)

    oauth_client = RecordingStudioApi::OauthClient.create!(
      name: "Session list app",
      client_identifier: "session-list-app",
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

    RecordingStudioApi::Services::ExchangeOauthAuthorizationCode.call(
      grant_type: "authorization_code",
      client_id: oauth_client.client_identifier,
      code: authorize_result.value.fetch(:code),
      redirect_uri: oauth_client.redirect_uri,
      code_verifier: code_verifier
    )

    @session = RecordingStudioApi::OauthGrantSession.order(created_at: :desc).first
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "lists active oauth grant sessions for selected access recording" do
    get "/recording_studio_api/oauth_grant_sessions", params: { access_recording_id: @access_recording.id }

    assert_response :success
    assert_includes response.body, "Mobile grant sessions"
    assert_includes response.body, "Session list app"
    assert_includes response.body, "Revoke"
  end

  test "revokes an oauth grant session from list action" do
    post "/recording_studio_api/oauth_grant_sessions/#{@session.id}/revoke"

    assert_redirected_to "/recording_studio_api/oauth_grant_sessions?access_recording_id=#{@access_recording.id}"
    assert_not_nil @session.reload.revoked_at
  end

  test "view-only access can view sessions but does not see revoke controls" do
    sign_out @user
    view_user = create_user(email: "oauth-view-only@example.com")
    sign_in view_user

    _view_root_recording, view_access_recording = create_access_recording_for(user: view_user, role: :view)

    oauth_client = RecordingStudioApi::OauthClient.create!(
      name: "View-only session app",
      client_identifier: "session-view-only-app",
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
      access_recording_id: view_access_recording.id
    )

    RecordingStudioApi::Services::ExchangeOauthAuthorizationCode.call(
      grant_type: "authorization_code",
      client_id: oauth_client.client_identifier,
      code: authorize_result.value.fetch(:code),
      redirect_uri: oauth_client.redirect_uri,
      code_verifier: code_verifier
    )

    get "/recording_studio_api/oauth_grant_sessions", params: { access_recording_id: view_access_recording.id }

    assert_response :success
    assert_includes response.body, "View-only session app"
    assert_select "form button", text: "Revoke", count: 0
    assert_includes response.body, "No revoke access"
  end
end
