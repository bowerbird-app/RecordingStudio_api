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

  test "creates access client beneath an api access point descendant" do
    folder_recording = RecordingStudio::Recording.create!(
      recordable: Folder.create!(name: "Folder access point"),
      parent_recording: @root_recording
    )

    result = RecordingStudioApi::Services::ProvisionAccessRequest.call(
      access_point_recording: folder_recording,
      actor: @user,
      role: :admin,
      api_client_name: "Folder scoped client"
    )

    assert result.success?, result.error
    assert_equal folder_recording.id, result.value.fetch(:access_recording).parent_recording_id
    assert_equal @root_recording.id, result.value.fetch(:access_recording).root_recording_id
  end

  test "rejects access points without the api access point capability" do
    folder_recording = RecordingStudio::Recording.create!(
      recordable: Folder.create!(name: "Blocked access point"),
      parent_recording: @root_recording
    )
    original_capability_enabled = RecordingStudio.method(:capability_enabled?)

    result = RecordingStudio.stub(:capability_enabled?, lambda do |capability, **kwargs|
      next false if capability == :api_access_point && kwargs[:for] == "Folder"

      original_capability_enabled.call(capability, **kwargs)
    end) do
      RecordingStudioApi::Services::ProvisionAccessRequest.call(
        access_point_recording: folder_recording,
        actor: @user,
        role: :admin,
        api_client_name: "Blocked folder client"
      )
    end

    assert result.failure?
    assert_equal "Access point recording does not allow API access", result.error
  end

  test "creates a separate access recording for each api client" do
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
    refute_equal first_result.value.fetch(:access_recording).id, second_result.value.fetch(:access_recording).id
    assert_equal first_result.value.fetch(:api_client), first_result.value.fetch(:access_recording).recordable.actor
    assert_equal second_result.value.fetch(:api_client), second_result.value.fetch(:access_recording).recordable.actor
    assert_equal @root_recording.id, second_result.value.fetch(:access_recording).parent_recording_id
    assert_equal "admin", second_result.value.fetch(:access_recording).recordable.role
    assert_nil first_result.value.fetch(:credential).reload.revoked_at
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

  test "prevents edit managers from provisioning admin API access" do
    edit_user = create_user(email: "edit-provision@example.com")
    edit_root_recording, = create_access_recording_for(user: edit_user, role: :edit)
    RecordingStudioApi.configuration.access_management_edit_role = :edit

    rejected_result = RecordingStudioApi::Services::ProvisionAccessRequest.call(
      access_point_recording: edit_root_recording,
      actor: edit_user,
      role: :admin,
      api_client_name: "Escalated client"
    )

    assert rejected_result.failure?
    assert_equal "Requested API access role exceeds the manager's access", rejected_result.error
    assert_equal 0, RecordingStudioApi::ApiClient.where(name: "Escalated client").count
  end
end