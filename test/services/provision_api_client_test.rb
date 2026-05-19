# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"

class ProvisionApiClientTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user)
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "provisions an immutable api client beneath the access recording" do
    result = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: @access_recording,
      name: "Primary token"
    )

    assert result.success?, result.error

    payload = result.value
    parsed_token = RecordingStudioApi::Token.parse(payload.fetch(:token))

    assert_equal @access_recording.id, payload.fetch(:api_client).access_recording_id
    assert_equal @access_recording.id, payload.fetch(:recording).parent_recording_id
    assert_equal payload.fetch(:api_client).id, payload.fetch(:credential).api_client_id
    assert_equal @access_recording.id, payload.fetch(:credential).effective_access_recording_id
    assert_equal payload.fetch(:recording).id, payload.fetch(:credential).recording.parent_recording_id
    assert_equal "RecordingStudioApi::ApiCredential", payload.fetch(:credential).recording.recordable_type
    assert_equal parsed_token.fetch(:public_id), payload.fetch(:credential).token_public_id
    assert_not_equal payload.fetch(:token), payload.fetch(:credential).token_digest
  end

  test "revokes the previous active credential when rotating the same access recording" do
    first = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: @access_recording,
      name: "First token"
    ).value

    second_result = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: @access_recording,
      name: "Second token"
    )

    assert second_result.success?, second_result.error

    assert_not_nil first.fetch(:credential).reload.revoked_at
    assert_nil second_result.value.fetch(:credential).reload.revoked_at
  end

  test "applies the configured token ttl when expires_at is omitted" do
    travel_to Time.zone.parse("2026-05-18 12:00:00 UTC") do
      RecordingStudioApi.configuration.token_ttl = 2.hours

      result = RecordingStudioApi::Services::ProvisionApiClient.call(
        access_recording: @access_recording,
        name: "TTL token"
      )

      assert result.success?, result.error
      assert_equal 2.hours.from_now, result.value.fetch(:credential).expires_at
    end
  end

  test "uses recording topology over legacy access_recording column" do
    result = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: @access_recording,
      name: "Compatibility token"
    )

    assert result.success?, result.error

    _other_root, other_access_recording = create_access_recording_for(
      user: @user,
      workspace_name: "Other workspace"
    )

    credential = result.value.fetch(:credential)
    credential.update_column(:access_recording_id, other_access_recording.id)

    assert_equal @access_recording.id, credential.reload.effective_access_recording_id
  end
end
