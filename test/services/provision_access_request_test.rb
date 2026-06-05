# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"

class ProvisionAccessRequestTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    Current.actor = @user
    @root_recording, @access_recording = create_access_recording_for(user: @user, workspace_name: "Provisioned Workspace", role: :admin)
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "creates access client and credential beneath the root recording" do
    result = RecordingStudioApi::Services::ProvisionAccessRequest.call(
      access_point_recording: @root_recording,
      actor: @user,
      role: :admin,
      api_client_name: "Workspace demo client"
    )

    assert result.success?, result.error

    payload = result.value

    assert_equal @root_recording.id, payload.fetch(:access_recording).root_recording_id
    assert_equal @root_recording.id, payload.fetch(:access_recording).parent_recording_id
    assert_equal "RecordingStudio::Access", payload.fetch(:access_recording).recordable_type
    assert_equal payload.fetch(:access_recording).id, payload.fetch(:api_client).access_recording_id
    assert_equal payload.fetch(:api_client).recording.id, payload.fetch(:credential).recording.parent_recording_id
    assert_not_empty payload.fetch(:token)
  end

  test "reuses the same access recording for repeated requests" do
    first_result = RecordingStudioApi::Services::ProvisionAccessRequest.call(
      access_point_recording: @root_recording,
      actor: @user,
      role: :view,
      api_client_name: "First client"
    )

    assert first_result.success?, first_result.error

    second_result = RecordingStudioApi::Services::ProvisionAccessRequest.call(
      access_point_recording: @root_recording,
      actor: @user,
      role: :admin,
      api_client_name: "Second client"
    )

    assert second_result.success?, second_result.error
    assert_equal first_result.value.fetch(:access_recording).id, second_result.value.fetch(:access_recording).id
    assert_equal @root_recording.id, second_result.value.fetch(:access_recording).parent_recording_id
    assert_equal "admin", second_result.value.fetch(:access_recording).recordable.role
    assert_not_nil first_result.value.fetch(:credential).reload.revoked_at
  end

  test "rejects provisioning for view-only access by default" do
    view_user = create_user(email: "view-provision@example.com")
    view_root_recording, = create_access_recording_for(user: view_user, role: :view)

    result = RecordingStudioApi::Services::ProvisionAccessRequest.call(
      access_point_recording: view_root_recording,
      actor: view_user,
      role: :view,
      api_client_name: "Blocked client"
    )

    assert result.failure?
    assert_equal "Actor is not authorized to manage API access for this recording", result.error
  end
end