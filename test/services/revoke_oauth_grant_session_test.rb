# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"
require "base64"
require "digest"

class RevokeOauthGrantSessionTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!

    @admin_user = create_user(email: "oauth-admin@example.com")
    @member_user = create_user(email: "oauth-member@example.com")

    @root_recording, @admin_access_recording = create_access_recording_for(user: @admin_user, role: :admin)
    setup_member_mobile_session!
    setup_admin_api_token!
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "rejects view-only session owner revoke by default" do
    result = RecordingStudioApi::Services::RevokeOauthGrantSession.call(
      oauth_grant_session_id: @member_session.id,
      authorization_header: "Bearer #{@member_mobile_access_token}"
    )

    assert result.failure?
    assert_equal "not authorized to revoke this oauth grant session", result.error.fetch(:error_description)
    assert_nil @member_session.reload.revoked_at
  end

  test "allows admin to revoke another access session in same root" do
    result = RecordingStudioApi::Services::RevokeOauthGrantSession.call(
      oauth_grant_session_id: @member_session.id,
      authorization_header: "Bearer #{@admin_api_token}"
    )

    assert result.success?, result.error
    assert_not_nil @member_session.reload.revoked_at
  end

  private

  def setup_member_mobile_session!
    Current.actor = @member_user
    member_access = RecordingStudio::Access.create!(actor: @member_user, role: :view)
    @member_access_recording = RecordingStudio::Recording.create!(
      recordable: member_access,
      parent_recording: @root_recording
    )

    @oauth_client = RecordingStudioApi::OauthClient.create!(
      name: "Mobile app",
      client_identifier: "mobile-app-admin-revoke",
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
      access_recording_id: @member_access_recording.id
    )

    exchange_result = RecordingStudioApi::Services::ExchangeOauthAuthorizationCode.call(
      grant_type: "authorization_code",
      client_id: @oauth_client.client_identifier,
      code: authorize_result.value.fetch(:code),
      redirect_uri: @oauth_client.redirect_uri,
      code_verifier: code_verifier
    )

    @member_mobile_access_token = exchange_result.value.fetch(:access_token)
    @member_session = RecordingStudioApi::OauthGrantSession.order(created_at: :desc).first
  end

  def setup_admin_api_token!
    admin_payload = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: @admin_access_recording,
      name: "admin control client"
    ).value
    admin_token_result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: admin_payload.fetch(:credential).oauth_client_id,
      client_secret: admin_payload.fetch(:token)
    )
    @admin_api_token = admin_token_result.value.fetch(:access_token)
  end
end
