# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "../test_helper"
require_relative "../dummy/config/environment"
require_relative "../support/api_dummy_helpers"

class ApiAccessClientsQueryTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  Context = Struct.new(:params, :current_actor, :root_recording, keyword_init: true)

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user)
    @payload = provision_api_client_for(access_recording: @access_recording, name: "Credential-free client")
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "returns a missing row for a visible API client without credentials" do
    remove_credential!

    rows = query(status: "missing")

    assert_equal 1, rows.size

    row = rows.first
    assert_equal @payload.fetch(:api_client).id, row.id
    assert_equal @payload.fetch(:api_client), row.api_client
    assert_nil row.api_credential
    assert_equal 0, row.credentials_count
    assert_equal "No credentials", row.status
    assert_equal "No credentials", row.expires_text
    assert_equal 0, row.request_count
    assert_nil row.last_requested_at
  end

  test "does not include a credential-free client in the default active filter" do
    remove_credential!

    assert_empty query
  end

  test "scopes visible clients to the selected API" do
    RecordingStudioApi.configuration.api(:operations)
    RecordingStudioApi.register_recordable_type_api("Workspace", api: :operations)
    operations_payload = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_point_recording: @root_recording,
      manager_actor: @user,
      role: :admin,
      name: "Operations client",
      api: :operations
    ).value

    assert_equal [@payload.fetch(:api_client).id], query.map { |row| row.api_client.id }.uniq
    assert_equal [operations_payload.fetch(:api_client).id], query(api_key: "operations").map { |row| row.api_client.id }.uniq
  end

  test "a folder admin sees keys under their folder only" do
    tree = build_folder_access
    owner = tree.fetch(:owner)
    folder_key = provisioned_client_id(tree.fetch(:folder), owner, "Folder key")
    child_key = provisioned_client_id(tree.fetch(:child), owner, "Child key")
    sibling_key = provisioned_client_id(tree.fetch(:sibling), owner, "Sibling key")
    root_key = provisioned_client_id(tree.fetch(:root), owner, "Root key")

    ids = visible_client_ids(actor: tree.fetch(:folder_admin), root_recording: tree.fetch(:root))

    assert_includes ids, folder_key
    assert_includes ids, child_key
    refute_includes ids, sibling_key
    refute_includes ids, root_key
    assert_empty visible_client_ids(actor: tree.fetch(:viewer), root_recording: tree.fetch(:root))
  end

  test "a dependent grant follows the manager chain" do
    tree = build_folder_access
    owner = tree.fetch(:owner)
    folder = tree.fetch(:folder)
    manager = create_user(email: "dependent-manager-#{SecureRandom.hex(4)}@example.com")
    grant_or_bootstrap_access!(recording: folder, actor: manager, role: :admin)
    manager_access = RecordingStudioAccessible.access_recordings_for_actor(recording: folder, actor: manager).first
    dependent_user = create_user(email: "dependent-actor-#{SecureRandom.hex(4)}@example.com")
    dependent = RecordingStudioAccessible.grant_access(
      recording: folder,
      actor: dependent_user,
      role: :admin,
      manager_actor: manager,
      depends_on: manager_access
    )
    assert dependent.success?, dependent.error

    folder_key = provisioned_client_id(folder, owner, "Dependent folder key")
    sibling_key = provisioned_client_id(tree.fetch(:sibling), owner, "Dependent sibling key")
    ids = visible_client_ids(actor: dependent_user, root_recording: tree.fetch(:root))

    assert_includes ids, folder_key
    refute_includes ids, sibling_key

    RecordingStudio::Access.where(id: manager_access.recordable_id).update_all(role: "view")
    constrained_ids = visible_client_ids(actor: dependent_user, root_recording: tree.fetch(:root))

    refute_includes constrained_ids, folder_key
    refute_includes constrained_ids, sibling_key
  end

  test "a multi-workspace actor sees each workspace's permitted keys" do
    first = build_folder_access
    actor = first.fetch(:folder_admin)
    second_owner = create_user(email: "second-workspace-#{SecureRandom.hex(4)}@example.com")
    second_root, = create_access_recording_for(user: second_owner, role: :admin, workspace_name: "Second workspace")
    grant_or_bootstrap_access!(recording: second_root, actor: actor, role: :admin)

    folder_key = provisioned_client_id(first.fetch(:folder), first.fetch(:owner), "First folder key")
    sibling_key = provisioned_client_id(first.fetch(:sibling), first.fetch(:owner), "First sibling key")
    second_key = provisioned_client_id(second_root, second_owner, "Second workspace key")

    calls = authorized_recording_calls do
      ids = visible_client_ids(actor: actor)

      assert_includes ids, folder_key
      assert_includes ids, second_key
      refute_includes ids, sibling_key
    end
    assert_equal 2, calls

    scoped_calls = authorized_recording_calls do
      scoped_ids = visible_client_ids(actor: actor, root_recording: first.fetch(:root))

      assert_includes scoped_ids, folder_key
      refute_includes scoped_ids, second_key
      refute_includes scoped_ids, sibling_key
    end
    assert_equal 1, scoped_calls
  end

  test "labels a root access point by type and a nested access point by its name" do
    tree = build_folder_access
    owner = tree.fetch(:owner)
    provisioned_client_id(tree.fetch(:root), owner, "Workspace root key")
    provisioned_client_id(tree.fetch(:folder), owner, "Workspace folder key")

    rows = RecordingStudioApi::Admin::Queries::ApiAccessClientsQuery.call(
      Context.new(params: {}, current_actor: owner, root_recording: tree.fetch(:root))
    )
    by_name = rows.index_by(&:name)

    assert_equal "Workspace", by_name.fetch("Workspace root key").access_point
    assert_equal "Managed folder", by_name.fetch("Workspace folder key").access_point
    assert tree.fetch(:root).root?
    refute tree.fetch(:folder).root?

    RecordingStudioApi::Admin::Queries::AdminApiCredentialsQuery.clear_cache!
    credential_rows = RecordingStudioApi::Admin::Queries::AdminApiCredentialsQuery.call.index_by { |row| row.api_client.name }

    assert_equal "Workspace", credential_rows.fetch("Workspace root key").access_point
    assert_equal "Managed folder", credential_rows.fetch("Workspace folder key").access_point
    assert credential_rows.fetch("Workspace root key").root_recording.root?
  end

  test "a folder id is not treated as a root scope" do
    tree = build_folder_access
    owner = tree.fetch(:owner)
    root_key = provisioned_client_id(tree.fetch(:root), owner, "Root stays")
    folder_key = provisioned_client_id(tree.fetch(:folder), owner, "Folder stays")

    ids = visible_client_ids(
      actor: owner,
      root_recording: tree.fetch(:root),
      params: { root_recording_id: tree.fetch(:folder).id }
    )

    assert_includes ids, root_key
    assert_includes ids, folder_key
  end

  test "a parentless recording of a non-root type is not a root for the type filter" do
    orphan = create_orphan_recording(parent_recording: @root_recording, title: "Query orphan")

    assert_nil orphan.parent_recording_id
    assert_equal orphan.id, orphan.root_recording_id
    assert_predicate orphan, :orphan?
    refute_predicate orphan, :root?

    page_scope = root_recordings_for("Page")
    workspace_scope = root_recordings_for("Workspace")

    refute_includes page_scope, orphan.id
    refute_includes workspace_scope, orphan.id
    assert_includes workspace_scope, @root_recording.id
  end

  test "a kept key under a trashed ancestor stays hidden" do
    tree = build_folder_access
    owner = tree.fetch(:owner)
    root = tree.fetch(:root)
    kept_key = provisioned_client_id(tree.fetch(:folder), owner, "Kept folder key")
    kept_child_key = provisioned_client_id(tree.fetch(:child), owner, "Kept child key")
    hidden_child = nested_folder_recording("Under the trashed folder", tree.fetch(:sibling))
    hidden_key = provisioned_client_id(hidden_child, owner, "Hidden grandchild key")
    tree.fetch(:sibling).update!(trashed_at: Time.current)

    from_root = visible_client_ids(actor: owner, root_recording: root, params: { include_children: true })

    assert_includes from_root, kept_key
    assert_includes from_root, kept_child_key
    refute_includes from_root, hidden_key

    from_trashed_seed = visible_client_ids(
      actor: owner,
      root_recording: root,
      params: { parent_recording_id: tree.fetch(:sibling).id, include_children: true }
    )

    assert_includes from_trashed_seed, hidden_key
    refute_includes from_trashed_seed, kept_key
  end

  test "a workspace admin sees every key in the workspace" do
    tree = build_folder_access
    owner = tree.fetch(:owner)
    ids = [
      provisioned_client_id(tree.fetch(:root), owner, "Workspace root key"),
      provisioned_client_id(tree.fetch(:folder), owner, "Workspace folder key"),
      provisioned_client_id(tree.fetch(:child), owner, "Workspace child key"),
      provisioned_client_id(tree.fetch(:sibling), owner, "Workspace sibling key")
    ]

    assert_equal ids.sort, visible_client_ids(actor: owner, root_recording: tree.fetch(:root)).sort
  end

  private

  def remove_credential!
    credential = @payload.fetch(:credential)
    credential.delete
  end

  def root_recordings_for(root_type)
    context = Context.new(
      params: { root_type: root_type },
      current_actor: @user,
      root_recording: @root_recording
    )

    RecordingStudioApi::Admin::Queries::ApiAccessClientsQuery.new(context).send(:root_recordings_for_type).pluck(:id)
  end

  def query(status: nil, api_key: nil)
    params = {}
    params[:status] = status if status
    params[:api_key] = api_key if api_key
    context = Context.new(params: params, current_actor: @user, root_recording: @root_recording)

    RecordingStudioApi::Admin::Queries::ApiAccessClientsQuery.call(context)
  end

  def provisioned_client_id(access_point, manager, name)
    result = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_point_recording: access_point,
      manager_actor: manager,
      role: :admin,
      name: name
    )
    assert result.success?, result.error.to_s

    result.value.fetch(:api_client).id
  end

  def visible_client_ids(actor:, root_recording: nil, params: {})
    context = Context.new(params: params, current_actor: actor, root_recording: root_recording)

    RecordingStudioApi::Admin::Queries::ApiAccessClientsQuery.call(context).map { |row| row.api_client.id }.uniq
  end

  def authorized_recording_calls
    calls = 0
    singleton = class << RecordingStudioAccessible; self; end
    singleton.alias_method(:authorized_recordings_without_count, :authorized_recordings)
    singleton.define_method(:authorized_recordings) do |*args, **kwargs, &block|
      calls += 1
      authorized_recordings_without_count(*args, **kwargs, &block)
    end
    yield
    calls
  ensure
    singleton.alias_method(:authorized_recordings, :authorized_recordings_without_count)
    singleton.remove_method(:authorized_recordings_without_count)
  end
end