# frozen_string_literal: true

require_relative "support/api_dummy_helpers"

class AccessManagementPolicyTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "view access can see but not manage access management" do
    user = create_user(email: "policy-view@example.com")
    root_recording, = create_access_recording_for(user: user, role: :view)

    policy = RecordingStudioApi::AccessManagementPolicy.new(actor: user)

    assert_includes policy.visible_root_recordings, root_recording
    refute_includes policy.manageable_root_recordings, root_recording
    assert policy.can_view_root_recording?(root_recording)
    refute policy.can_manage_root_recording?(root_recording)
  end

  test "admin access can manage access management" do
    user = create_user(email: "policy-admin@example.com")
    root_recording, = create_access_recording_for(user: user, role: :admin)

    policy = RecordingStudioApi::AccessManagementPolicy.new(actor: user)

    assert_includes policy.visible_root_recordings, root_recording
    assert_includes policy.manageable_root_recordings, root_recording
    assert policy.can_manage_root_recording?(root_recording)
  end

  test "descendant access recording visibility follows RecordingStudioAccessible authorization" do
    user = create_user(email: "policy-descendant@example.com")
    workspace = Workspace.create!(name: "Scoped Workspace")
    root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    folder = Folder.create!(name: "Admin API")
    folder_recording = RecordingStudio::Recording.create!(recordable: folder, parent_recording: root_recording)
    access_recording = with_access_creation_context do
      access = RecordingStudio::Access.create!(actor: user, role: :view)
      RecordingStudio::Recording.create!(recordable: access, parent_recording: folder_recording)
    end

    policy = RecordingStudioApi::AccessManagementPolicy.new(actor: user)

    assert_includes policy.visible_access_recordings, access_recording
    assert_includes policy.visible_root_recordings, root_recording
    assert policy.can_view_root_recording?(root_recording)
    assert policy.authorized_for_access_recording?(access_recording, access_management_role: :view)
  end

  test "api client access recordings are visible to managers of their access point" do
    user = create_user(email: "policy-api-client@example.com")
    root_recording, manager_access_recording = create_access_recording_for(user: user, role: :admin)

    result = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: manager_access_recording,
      name: "Managed API client"
    )

    assert result.success?, result.error

    api_client_access_recording = result.value.fetch(:access_recording)
    policy = RecordingStudioApi::AccessManagementPolicy.new(actor: user)

    assert_equal result.value.fetch(:api_client), api_client_access_recording.recordable.actor
    assert_includes policy.visible_api_client_access_recordings, api_client_access_recording
    assert_includes policy.manageable_api_client_access_recordings, api_client_access_recording
    assert_includes policy.visible_access_recordings, manager_access_recording
    refute_includes policy.visible_access_recordings, api_client_access_recording
    assert policy.authorized_for_access_recording?(api_client_access_recording, access_management_role: :admin)
    assert_equal root_recording.id, api_client_access_recording.root_recording_id
  end
end
