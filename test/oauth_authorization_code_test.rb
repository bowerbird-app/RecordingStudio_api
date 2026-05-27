# frozen_string_literal: true

require_relative "support/api_dummy_helpers"

class OauthAuthorizationCodeTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!

    @user = create_user(email: "oauth-code-model@example.com")
    @_root_recording, @access_recording = create_access_recording_for(user: @user)
    @oauth_client = RecordingStudioApi::OauthClient.create!(
      name: "Model Test Client",
      client_identifier: "model-test-client",
      redirect_uri: "myapp://oauth/callback"
    )
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "active scope and active predicate only include unconsumed unexpired codes" do
    active_code = build_code(expires_at: 10.minutes.from_now)
    expired_code = build_code(expires_at: 5.minutes.ago)
    consumed_code = build_code(expires_at: 10.minutes.from_now, consumed_at: Time.current)

    assert_equal true, active_code.active?
    assert_equal false, expired_code.active?
    assert_equal false, consumed_code.active?

    active_ids = RecordingStudioApi::OauthAuthorizationCode.active.pluck(:id)

    assert_includes active_ids, active_code.id
    assert_not_includes active_ids, expired_code.id
    assert_not_includes active_ids, consumed_code.id
  end

  test "consume updates consumed_at and updated_at" do
    authorization_code = build_code(expires_at: 10.minutes.from_now)
    timestamp = Time.current.change(usec: 0)

    authorization_code.consume!(time: timestamp)
    authorization_code.reload

    assert_equal timestamp, authorization_code.consumed_at
    assert_equal timestamp, authorization_code.updated_at
  end

  private

  def build_code(expires_at:, consumed_at: nil)
    code = RecordingStudioApi::OauthAuthorizationCode.new(
      oauth_client: @oauth_client,
      access_recording: @access_recording,
      code_digest: SecureRandom.hex(16),
      code_prefix: SecureRandom.hex(4),
      code_challenge: SecureRandom.base64(32),
      code_challenge_method: "S256",
      redirect_uri: @oauth_client.redirect_uri,
      expires_at: expires_at,
      consumed_at: consumed_at
    )
    code.save!(validate: false)
    code
  end
end