# frozen_string_literal: true

require "test_helper"

class IntegrationResultTest < Minitest::Test
  def test_access_grant_from_header_returns_a_core_result
    client = RecordingStudioApi::AuthenticatedClient.new(
      api_client: Object.new,
      credential: nil,
      access_recording: Object.new,
      root_recording: Object.new,
      api_key: "public"
    )
    authenticated = RecordingStudio::Services::BaseService::Result.new(success: true, value: client)

    RecordingStudioApi::Services::AuthenticateOauthAccessToken.stub(:call, authenticated) do
      result = RecordingStudioApi::Integration.access_grant_from_authorization_header(
        authorization_header: "Bearer present"
      )

      assert_instance_of RecordingStudio::Services::BaseService::Result, result
      assert result.success?
      assert_instance_of RecordingStudioApi::AccessGrant, result.value
      assert_equal client.api_client, result.value.api_client
      assert_respond_to result, :error
      assert_respond_to result, :errors
      assert_respond_to result, :on_success
      assert_respond_to result, :on_failure
      assert_respond_to result, :value!
    end
  end

  def test_failed_header_keeps_the_authenticator_result
    result = RecordingStudioApi::Integration.access_grant_from_authorization_header(authorization_header: nil)

    assert_instance_of RecordingStudio::Services::BaseService::Result, result
    assert result.failure?
    assert_nil result.value
  end
end
