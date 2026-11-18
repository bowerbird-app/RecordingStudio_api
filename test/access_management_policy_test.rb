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

  test "assignable roles do not exceed the manager's effective role" do
    user = create_user(email: "policy-edit@example.com")
    root_recording, = create_access_recording_for(user: user, role: :edit)
    RecordingStudioApi.configuration.access_management_edit_role = :edit

    policy = RecordingStudioApi::AccessManagementPolicy.new(actor: user)

    assert_equal :edit, policy.maximum_assignable_role_for(root_recording)
    assert_equal :edit, RecordingStudioAccessible.role_for(actor: user, recording: root_recording)
    assert policy.can_assign_role?(root_recording, :view)
    assert policy.can_assign_role?(root_recording, :edit)
    refute policy.can_assign_role?(root_recording, :admin)
    refute policy.can_assign_role?(root_recording, :owner)
  end

  test "a viewer cannot assign above the role they hold" do
    user = create_user(email: "policy-ceiling-view@example.com")
    root_recording, = create_access_recording_for(user: user, role: :view)
    RecordingStudioApi.configuration.access_management_edit_role = :view

    policy = RecordingStudioApi::AccessManagementPolicy.new(actor: user)

    assert policy.can_manage_recording?(root_recording)
    assert_equal :view, policy.maximum_assignable_role_for(root_recording)
    assert policy.can_assign_role?(root_recording, :view)
    refute policy.can_assign_role?(root_recording, :edit)
    refute policy.can_assign_role?(root_recording, :admin)
  end

  test "an inherited role several levels up is the assignable ceiling" do
    tree = build_folder_access
    grandchild = nested_folder_recording("Grandchild", tree.fetch(:child))
    great_grandchild = nested_folder_recording("Great grandchild", grandchild)
    folder_policy = RecordingStudioApi::AccessManagementPolicy.new(actor: tree.fetch(:folder_admin))

    assert_equal :admin, RecordingStudioAccessible.role_for(actor: tree.fetch(:folder_admin), recording: great_grandchild)
    assert_equal :admin, folder_policy.maximum_assignable_role_for(great_grandchild)
    assert folder_policy.can_assign_role?(great_grandchild, :admin)
    refute folder_policy.can_assign_role?(great_grandchild, :owner)
    assert_equal :view, folder_policy.maximum_assignable_role_for(tree.fetch(:root))
    refute folder_policy.can_assign_role?(tree.fetch(:root), :view)

    editor = create_user(email: "policy-deep-edit-#{SecureRandom.hex(4)}@example.com")
    grant_or_bootstrap_access!(recording: tree.fetch(:root), actor: editor, role: :edit)
    RecordingStudioApi.configuration.access_management_edit_role = :edit
    editor_policy = RecordingStudioApi::AccessManagementPolicy.new(actor: editor)

    assert_equal :edit, editor_policy.maximum_assignable_role_for(great_grandchild)
    assert editor_policy.can_assign_role?(great_grandchild, :edit)
    refute editor_policy.can_assign_role?(great_grandchild, :admin)
  end

  test "a trashed descendant keeps the inherited assignable role" do
    user = create_user(email: "policy-trashed-assign@example.com")
    root_recording, = create_access_recording_for(user: user, role: :edit)
    folder = nested_folder_recording("Trashed parent", root_recording)
    page = nested_folder_recording("Trashed page", folder)
    page.update_column(:trashed_at, Time.current)
    page.reload
    RecordingStudioApi.configuration.access_management_edit_role = :edit

    policy = RecordingStudioApi::AccessManagementPolicy.new(actor: user)

    assert_equal false, page.kept?
    assert_equal :edit, RecordingStudioAccessible.role_for(actor: user, recording: page)
    assert_equal :edit, policy.maximum_assignable_role_for(page)
    assert policy.can_assign_role?(page, :view)
    assert policy.can_assign_role?(page, :edit)
    refute policy.can_assign_role?(page, :admin)
  end

  test "missing actor access cannot assign a role" do
    root_recording, = create_access_recording_for(user: create_user, role: :admin)
    stranger = create_user(email: "policy-stranger-#{SecureRandom.hex(4)}@example.com")
    stranger_policy = RecordingStudioApi::AccessManagementPolicy.new(actor: stranger)
    blank_policy = RecordingStudioApi::AccessManagementPolicy.new(actor: nil)

    assert_nil stranger_policy.maximum_assignable_role_for(root_recording)
    refute stranger_policy.can_assign_role?(root_recording, :view)
    assert_nil blank_policy.maximum_assignable_role_for(root_recording)
    refute blank_policy.can_assign_role?(root_recording, :view)
    assert_nil stranger_policy.maximum_assignable_role_for(nil)
    refute stranger_policy.can_assign_role?(nil, :admin)
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
    refute policy.can_view_recording?(root_recording)
    refute policy.can_manage_recording?(folder_recording)
    assert policy.can_view_recording?(folder_recording)
    assert policy.authorized_for_access_recording?(access_recording, access_management_role: :view)
  end

  test "a folder admin manages that folder and its descendants only" do
    tree = build_folder_access
    policy = RecordingStudioApi::AccessManagementPolicy.new(actor: tree.fetch(:folder_admin))
    managed_ids = policy.manageable_recordings.map(&:id)

    assert_includes managed_ids, tree.fetch(:folder).id
    assert_includes managed_ids, tree.fetch(:child).id
    refute_includes managed_ids, tree.fetch(:sibling).id
    refute_includes managed_ids, tree.fetch(:root).id
    refute_includes policy.manageable_root_recordings, tree.fetch(:root)
    assert policy.can_manage_recording?(tree.fetch(:folder))
    assert policy.can_manage_recording?(tree.fetch(:child))
    refute policy.can_manage_recording?(tree.fetch(:sibling))
    refute policy.can_manage_recording?(tree.fetch(:root))
    assert policy.can_view_recording?(tree.fetch(:root))
    assert policy.can_view_recording?(tree.fetch(:sibling))
    assert policy.can_assign_role?(tree.fetch(:folder), :admin)
    refute policy.can_assign_role?(tree.fetch(:sibling), :view)
    refute policy.can_assign_role?(tree.fetch(:root), :view)
    assert policy.can_manage_any_recording?

    folder_only = create_user(email: "folder-only-#{SecureRandom.hex(4)}@example.com")
    grant_or_bootstrap_access!(recording: tree.fetch(:folder), actor: folder_only, role: :admin)
    only_policy = RecordingStudioApi::AccessManagementPolicy.new(actor: folder_only)

    assert only_policy.can_manage_recording?(tree.fetch(:folder))
    assert only_policy.can_manage_recording?(tree.fetch(:child))
    refute only_policy.can_view_recording?(tree.fetch(:root))
    refute only_policy.can_manage_recording?(tree.fetch(:root))
    refute only_policy.can_manage_recording?(tree.fetch(:sibling))
    refute_includes only_policy.manageable_root_recordings, tree.fetch(:root)
  end

  test "a viewer cannot manage recordings they can view" do
    tree = build_folder_access
    policy = RecordingStudioApi::AccessManagementPolicy.new(actor: tree.fetch(:viewer))

    assert policy.can_view_recording?(tree.fetch(:folder))
    assert policy.can_view_recording?(tree.fetch(:child))
    refute policy.can_view_recording?(tree.fetch(:sibling))
    refute policy.can_view_recording?(tree.fetch(:root))
    refute policy.can_manage_recording?(tree.fetch(:folder))
    refute policy.can_manage_recording?(tree.fetch(:child))
    refute policy.can_manage_any_recording?
    assert_empty policy.manageable_recordings
    assert_empty policy.manageable_root_recordings
  end

  test "a workspace admin manages the root and every folder" do
    tree = build_folder_access
    policy = RecordingStudioApi::AccessManagementPolicy.new(actor: tree.fetch(:owner))

    assert_includes policy.manageable_root_recordings, tree.fetch(:root)
    assert policy.can_manage_recording?(tree.fetch(:root))
    assert policy.can_manage_recording?(tree.fetch(:folder))
    assert policy.can_manage_recording?(tree.fetch(:child))
    assert policy.can_manage_recording?(tree.fetch(:sibling))
    assert policy.can_assign_role?(tree.fetch(:root), :admin)
    assert policy.can_manage_any_recording?
  end

  test "api keys screen manage follows the access point" do
    tree = build_folder_access

    assert api_keys_screen_manageable?(tree.fetch(:folder_admin), tree.fetch(:folder))
    assert api_keys_screen_manageable?(tree.fetch(:folder_admin), tree.fetch(:child))
    refute api_keys_screen_manageable?(tree.fetch(:folder_admin), tree.fetch(:sibling))
    refute api_keys_screen_manageable?(tree.fetch(:folder_admin), tree.fetch(:root))
    refute api_keys_screen_manageable?(tree.fetch(:viewer), tree.fetch(:folder))
    assert api_keys_screen_manageable?(tree.fetch(:owner), tree.fetch(:root))
    assert api_keys_screen_manageable?(tree.fetch(:owner), tree.fetch(:sibling))
    assert api_keys_screen_manageable?(tree.fetch(:owner), tree.fetch(:child))
  end

  test "test credential access points follow manageable recordings" do
    tree = build_folder_access
    host = Object.new
    host.extend(PublicApi::ScalarTestAuth)
    host.define_singleton_method(:scalar_test_auth_actor) { tree.fetch(:folder_admin) }
    ids = host.send(:scalar_test_auth_access_points).map { |entry| entry.fetch(:id) }

    assert_includes ids, tree.fetch(:folder).id
    assert_includes ids, tree.fetch(:child).id
    refute_includes ids, tree.fetch(:sibling).id
    refute_includes ids, tree.fetch(:root).id

    host.define_singleton_method(:scalar_test_auth_actor) { tree.fetch(:owner) }
    host.instance_variable_set(:@scalar_test_auth_policy, nil)
    owner_ids = host.send(:scalar_test_auth_access_points).map { |entry| entry.fetch(:id) }
    assert_includes owner_ids, tree.fetch(:root).id
    assert_includes owner_ids, tree.fetch(:sibling).id
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

  private

  def api_keys_screen_manageable?(actor, recording)
    row = Struct.new(:access_point_recording).new(recording)
    context = Struct.new(:current_actor).new(actor)
    RecordingStudioApi::Admin::ApiKeysScreen.manageable?(row, context)
  end
end
