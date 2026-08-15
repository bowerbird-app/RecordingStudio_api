# frozen_string_literal: true

require_relative "support/api_dummy_helpers"

class TokenDigestTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
  end

  teardown do
    reset_recording_studio_api_configuration!
  end

  test "stores peppered digests for newly generated tokens" do
    token_data = RecordingStudioApi::Token.generate
    access_token_data = RecordingStudioApi::OauthAccessToken.generate

    assert_equal RecordingStudioApi::TokenDigest.peppered_digest(token_data.fetch(:token)), token_data.fetch(:digest)
    assert_equal RecordingStudioApi::TokenDigest.peppered_digest(access_token_data.fetch(:token)), access_token_data.fetch(:digest)
    refute_equal RecordingStudioApi::TokenDigest.legacy_digest(token_data.fetch(:token)), token_data.fetch(:digest)
  end

  test "accepts legacy sha256 digests while legacy verify is enabled" do
    RecordingStudioApi.configuration.token_digest_legacy_verify = true
    secret = "rsapi_abcd1234.legacy-secret-value"
    legacy_digest = RecordingStudioApi::TokenDigest.legacy_digest(secret)

    assert RecordingStudioApi::Token.digest_matches?(legacy_digest, secret)
  end

  test "rejects legacy digests when legacy verify is disabled" do
    RecordingStudioApi.configuration.token_digest_legacy_verify = false
    secret = "rsapi_abcd1234.legacy-secret-value"
    legacy_digest = RecordingStudioApi::TokenDigest.legacy_digest(secret)

    refute RecordingStudioApi::Token.digest_matches?(legacy_digest, secret)
    assert RecordingStudioApi::Token.digest_matches?(RecordingStudioApi::Token.digest(secret), secret)
  end

  test "rehashes legacy credential digests after a successful match" do
    RecordingStudioApi.configuration.token_digest_legacy_verify = true
    user = create_user
    _root, access_recording = create_access_recording_for(user: user)
    payload = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: access_recording,
      name: "Legacy digest client"
    ).value
    credential = payload.fetch(:credential)
    secret = payload.fetch(:token)

    credential.update_columns(token_digest: RecordingStudioApi::TokenDigest.legacy_digest(secret))

    result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: credential.oauth_client_id,
      client_secret: secret
    )

    assert result.success?, result.error
    assert_equal RecordingStudioApi::Token.digest(secret), credential.reload.token_digest
  end

  test "raises when no digest pepper or secret_key_base is available" do
    RecordingStudioApi.configuration.token_digest_pepper = nil
    fake_app = Struct.new(:secret_key_base).new(nil)

    Rails.stub(:application, fake_app) do
      error = assert_raises(RecordingStudioApi::ConfigurationError) do
        RecordingStudioApi::TokenDigest.pepper
      end
      assert_match(/token_digest_pepper is required/, error.message)
    end
  end
end
