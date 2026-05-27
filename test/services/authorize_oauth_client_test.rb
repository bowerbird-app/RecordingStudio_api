# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"
require "digest"
require "securerandom"

class AuthorizeOauthClientTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    user = create_user
    _root_recording, @access_recording = create_access_recording_for(user: user)

    @oauth_client = RecordingStudioApi::OauthClient.create!(
      name: "Mobile app",
      client_identifier: "mobile-app-1",
      redirect_uri: "myapp://oauth/callback"
    )
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "issues authorization code for valid pkce request" do
    result = RecordingStudioApi::Services::AuthorizeOauthClient.call(
      response_type: "code",
      client_id: @oauth_client.client_identifier,
      redirect_uri: @oauth_client.redirect_uri,
      code_challenge: "z7Qv8FnT9C1qT6fM2f0fQf5K5pCtjHCM8Uo-UNfQ2Q4",
      code_challenge_method: "S256",
      access_recording_id: @access_recording.id,
      state: "state-123"
    )

    assert result.success?, result.error
    value = result.value
    assert_not_nil value.fetch(:code)
    assert_equal @oauth_client.redirect_uri, value.fetch(:redirect_uri)
    assert_equal "state-123", value.fetch(:state)

    created = RecordingStudioApi::OauthAuthorizationCode.order(created_at: :desc).first
    assert_not_nil created
    assert_equal @oauth_client.id, created.oauth_client_id
    assert_equal @access_recording.id, created.access_recording_id
    assert_equal Digest::SHA256.hexdigest(value.fetch(:code)), created.code_digest
    assert_not_nil created.recording
    assert_equal @access_recording.id, created.recording.parent_recording_id
  end

  test "rejects non-s256 code challenge method" do
    result = RecordingStudioApi::Services::AuthorizeOauthClient.call(
      response_type: "code",
      client_id: @oauth_client.client_identifier,
      redirect_uri: @oauth_client.redirect_uri,
      code_challenge: "z7Qv8FnT9C1qT6fM2f0fQf5K5pCtjHCM8Uo-UNfQ2Q4",
      code_challenge_method: "plain",
      access_recording_id: @access_recording.id
    )

    assert result.failure?
    assert_equal "invalid_request", result.error.fetch(:error)
  end

  test "rejects mismatched redirect uri" do
    result = RecordingStudioApi::Services::AuthorizeOauthClient.call(
      response_type: "code",
      client_id: @oauth_client.client_identifier,
      redirect_uri: "myapp://oauth/other",
      code_challenge: "z7Qv8FnT9C1qT6fM2f0fQf5K5pCtjHCM8Uo-UNfQ2Q4",
      code_challenge_method: "S256",
      access_recording_id: @access_recording.id
    )

    assert result.failure?
    assert_equal "invalid_request", result.error.fetch(:error)
  end

  test "rejects missing access recording" do
    result = RecordingStudioApi::Services::AuthorizeOauthClient.call(
      response_type: "code",
      client_id: @oauth_client.client_identifier,
      redirect_uri: @oauth_client.redirect_uri,
      code_challenge: "z7Qv8FnT9C1qT6fM2f0fQf5K5pCtjHCM8Uo-UNfQ2Q4",
      code_challenge_method: "S256",
      access_recording_id: SecureRandom.uuid
    )

    assert result.failure?
    assert_equal "invalid_scope", result.error.fetch(:error)
  end
end