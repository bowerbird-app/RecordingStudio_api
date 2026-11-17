# frozen_string_literal: true

require "digest"
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
    refute_equal Digest::SHA256.hexdigest(token_data.fetch(:token)), token_data.fetch(:digest)
  end

  test "rejects an unsalted sha256 digest" do
    secret = "rsapi_abcd1234.legacy-secret-value"
    unsalted = Digest::SHA256.hexdigest(secret)

    refute RecordingStudioApi::Token.digest_matches?(unsalted, secret)
    assert RecordingStudioApi::Token.digest_matches?(RecordingStudioApi::Token.digest(secret), secret)
  end

  test "does not authenticate or rewrite an unsalted credential digest" do
    user = create_user
    _root, access_recording = create_access_recording_for(user: user)
    payload = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: access_recording,
      name: "Legacy digest client"
    ).value
    credential = payload.fetch(:credential)
    secret = payload.fetch(:token)
    unsalted = Digest::SHA256.hexdigest(secret)
    credential.update_columns(token_digest: unsalted)

    result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: credential.oauth_client_id,
      client_secret: secret
    )

    assert result.failure?
    assert_equal unsalted, credential.reload.token_digest
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
