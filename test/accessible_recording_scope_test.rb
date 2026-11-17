# frozen_string_literal: true

require_relative "support/api_dummy_helpers"

class AccessibleRecordingScopeTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "includes the non-trashed subtree rooted at the scoped recording" do
    root_recording, access_recording = create_access_recording_for(user: @user, role: :edit)
    visible_page = create_page_recording(root_recording: root_recording)
    nested_folder = Folder.create!(name: "Nested")
    nested_folder_recording = RecordingStudio::Recording.create!(
      recordable: nested_folder,
      parent_recording: root_recording
    )
    nested_page = create_page_recording(
      root_recording: root_recording,
      parent_recording: nested_folder_recording
    )
    grant = access_grant_for(access_recording, root_recording)

    ids = grant.accessible_recordings.pluck(:id)

    assert_includes ids, root_recording.id
    assert_includes ids, visible_page.id
    assert_includes ids, nested_folder_recording.id
    assert_includes ids, nested_page.id
  end

  test "excludes trashed descendants from the scoped subtree" do
    root_recording, access_recording = create_access_recording_for(user: @user, role: :admin)
    folder = Folder.create!(name: "Trashed Folder")
    folder_recording = RecordingStudio::Recording.create!(recordable: folder, parent_recording: root_recording)
    page_recording = create_page_recording(
      root_recording: root_recording,
      parent_recording: folder_recording
    )
    page_recording.update_column(:trashed_at, Time.current)
    grant = access_grant_for(access_recording, root_recording)

    ids = grant.accessible_recordings.pluck(:id)

    assert_includes ids, folder_recording.id
    assert_not_includes ids, page_recording.id
  end

  test "can include trashed descendants when requested" do
    root_recording, access_recording = create_access_recording_for(user: @user, role: :admin)
    page_recording = create_page_recording(root_recording: root_recording)
    page_recording.update_column(:trashed_at, Time.current)
    grant = access_grant_for(access_recording, root_recording)

    ids = grant.accessible_recordings(include_trashed: true).pluck(:id)

    assert_includes ids, page_recording.id
  end

  test "memoizes recording ids for repeated authorization checks" do
    root_recording, access_recording = create_access_recording_for(user: @user, role: :edit)
    page_recording = create_page_recording(root_recording: root_recording)
    grant = access_grant_for(access_recording, root_recording)

    first_ids = grant.accessible_recording_ids
    second_ids = grant.accessible_recording_ids

    assert_same first_ids, second_ids
    assert_includes first_ids, page_recording.id
    assert grant.accessible_recordings.exists?(id: page_recording.id)
  end

  test "returns an empty relation when the grant has no anchor" do
    _root_recording, access_recording = create_access_recording_for(user: @user, role: :admin)
    grant = RecordingStudioApi::AccessGrant.new(
      api_client: nil,
      credential: nil,
      access_recording: nil,
      root_recording: nil
    )

    assert_empty grant.accessible_recordings.to_a
    assert access_recording.root_recording_id.present?
  end

  test "returns an empty relation when the access recording is not an access grant" do
    root_recording, = create_access_recording_for(user: @user, role: :admin)
    grant = RecordingStudioApi::AccessGrant.new(
      api_client: nil,
      credential: nil,
      access_recording: root_recording,
      root_recording: root_recording
    )

    assert_empty grant.accessible_recordings.to_a
  end

  test "a root grant uses the fast path and stays a relation" do
    root_recording, access_recording = create_access_recording_for(user: @user, role: :edit)
    page_recording = create_page_recording(root_recording: root_recording)
    grant = access_grant_for(access_recording, root_recording)
    queries = capture_sql { grant.accessible_recordings.pluck(:id) }
    sql = queries.join("\n")

    refute_includes sql, "WITH RECURSIVE"
    refute_includes sql, "scope_tree"
    assert_includes sql, "root_recording_id"
    refute_match(/IN \(\$\d+, \$\d+/, sql)
    assert_equal grant.accessible_recording_ids.sort, grant.accessible_recordings.pluck(:id).sort
    assert_includes grant.accessible_recordings.pluck(:id), page_recording.id
  end

  test "hides a trashed descendant unless include_trashed is set" do
    root_recording, access_recording = create_access_recording_for(user: @user, role: :edit)
    page_recording = create_page_recording(root_recording: root_recording)
    page_recording.update_column(:trashed_at, Time.current)
    grant = access_grant_for(access_recording, root_recording)

    assert_not_includes grant.accessible_recordings.pluck(:id), page_recording.id
    assert_not_includes grant.accessible_recording_ids, page_recording.id
    assert_includes grant.accessible_recordings(include_trashed: true).pluck(:id), page_recording.id
    assert_includes grant.accessible_recording_ids(include_trashed: true), page_recording.id
  end

  test "keeps a recording under a trashed folder visible" do
    root_recording, access_recording = create_access_recording_for(user: @user, role: :edit)
    folder = Folder.create!(name: "Trashed parent")
    folder_recording = RecordingStudio::Recording.create!(recordable: folder, parent_recording: root_recording)
    kept_page = create_page_recording(root_recording: root_recording, parent_recording: folder_recording)
    folder_recording.update_column(:trashed_at, Time.current)
    grant = access_grant_for(access_recording, root_recording)

    visible_ids = grant.accessible_recordings.pluck(:id)
    assert_not_includes visible_ids, folder_recording.id
    assert_includes visible_ids, kept_page.id
    assert_includes grant.accessible_recordings(include_trashed: true).pluck(:id), kept_page.id
    assert_includes grant.accessible_recordings(include_trashed: true).pluck(:id), folder_recording.id
  end

  test "a folder grant cannot see a sibling folder or a second root" do
    root_recording, = create_access_recording_for(user: @user, role: :admin)
    folder = Folder.create!(name: "Granted")
    folder_recording = RecordingStudio::Recording.create!(recordable: folder, parent_recording: root_recording)
    sibling = RecordingStudio::Recording.create!(
      recordable: Folder.create!(name: "Sibling"),
      parent_recording: root_recording
    )
    child = RecordingStudio::Recording.create!(
      recordable: Folder.create!(name: "Child"),
      parent_recording: folder_recording
    )
    other_root, = create_access_recording_for(user: create_user, role: :admin, workspace_name: "Second root")
    member = create_user
    access_recording = create_access_recording(parent_recording: folder_recording, user: member, role: :edit)
    grant = access_grant_for(access_recording, root_recording)

    visible_ids = grant.accessible_recordings.pluck(:id)
    assert_includes visible_ids, folder_recording.id
    assert_includes visible_ids, child.id
    assert_not_includes visible_ids, sibling.id
    assert_not_includes visible_ids, other_root.id
    assert_not_includes visible_ids, root_recording.id
    assert_includes grant.accessible_recordings.to_sql, "WITH RECURSIVE"
    assert_equal visible_ids.sort, grant.accessible_recording_ids.sort
  end

  test "a wrapped client uses the access actor's stored owner" do
    root_recording, = create_access_recording_for(user: @user, role: :admin)
    page_recording = create_page_recording(root_recording: root_recording)
    client = RecordingStudioApi::ApiClient.create!(name: "Wrapped key", api_key: "public", owner: @user)
    access_recording = grant_or_bootstrap_access!(recording: root_recording, actor: client, role: :edit)
    grant = RecordingStudioApi::AccessGrant.new(
      api_client: Object.new,
      credential: nil,
      access_recording: access_recording,
      root_recording: root_recording
    )

    assert_equal @user, grant.owner
    assert grant.authorized?(recording: page_recording, role: :view)
    refute grant.authorized?(recording: page_recording, role: :admin)
  end

  test "an api client with no owner sees nothing" do
    root_recording, = create_access_recording_for(user: @user, role: :admin)
    page_recording = create_page_recording(root_recording: root_recording)
    client = RecordingStudioApi::ApiClient.create!(name: "Orphan key", api_key: "public")
    access_recording = grant_or_bootstrap_access!(recording: root_recording, actor: client, role: :admin)
    grant = RecordingStudioApi::AccessGrant.new(
      api_client: client,
      credential: nil,
      access_recording: access_recording,
      root_recording: root_recording
    )

    assert_nil client.owner
    assert_empty grant.accessible_recordings.pluck(:id)
    refute grant.authorized?(recording: page_recording, role: :view)

    owned_client = RecordingStudioApi::ApiClient.create!(name: "Owned key", api_key: "public", owner: @user)
    owned = RecordingStudioApi::AccessGrant.new(
      api_client: owned_client,
      credential: nil,
      access_recording: access_recording,
      root_recording: root_recording
    )
    assert_equal @user, owned_client.owner
    assert_includes owned.accessible_recordings.pluck(:id), page_recording.id
  end

  test "grant role narrower than the owner role is enforced" do
    root_recording, access_recording = create_access_recording_for(user: @user, role: :admin)
    page_recording = create_page_recording(root_recording: root_recording)
    client = RecordingStudioApi::ApiClient.create!(name: "Narrow key", api_key: "public", owner: @user)
    client_access = grant_or_bootstrap_access!(recording: root_recording, actor: client, role: :view)
    grant = RecordingStudioApi::AccessGrant.new(
      api_client: client,
      credential: nil,
      access_recording: client_access,
      root_recording: root_recording
    )

    assert_equal :admin, RecordingStudioAccessible.role_for(actor: @user, recording: root_recording)
    assert_equal "view", client_access.recordable.role.to_s
    assert_equal "admin", access_recording.recordable.role.to_s
    assert grant.authorized?(recording: page_recording, role: :view)
    refute grant.authorized?(recording: page_recording, role: :edit)
  end

  test "owner role narrower than the grant role is enforced" do
    root_recording, access_recording = create_access_recording_for(user: @user, role: :view)
    page_recording = create_page_recording(root_recording: root_recording)
    client = RecordingStudioApi::ApiClient.create!(name: "Wide key", api_key: "public", owner: @user)
    client_access = grant_or_bootstrap_access!(recording: root_recording, actor: client, role: :admin)
    grant = RecordingStudioApi::AccessGrant.new(
      api_client: client,
      credential: nil,
      access_recording: client_access,
      root_recording: root_recording
    )

    assert_equal "admin", client_access.recordable.role.to_s
    assert_equal "view", access_recording.recordable.role.to_s
    assert grant.authorized?(recording: page_recording, role: :view)
    refute grant.authorized?(recording: page_recording, role: :edit)
  end

  test "relationship targets outside the subquery stay hidden" do
    root_recording, = create_access_recording_for(user: @user, role: :admin)
    folder_recording = RecordingStudio::Recording.create!(
      recordable: Folder.create!(name: "Granted"),
      parent_recording: root_recording
    )
    visible = RecordingStudio::Recording.create!(
      recordable: Folder.create!(name: "Child"),
      parent_recording: folder_recording
    )
    sibling = RecordingStudio::Recording.create!(
      recordable: Folder.create!(name: "Sibling"),
      parent_recording: root_recording
    )
    other_root, = create_access_recording_for(user: create_user, role: :edit, workspace_name: "Other root")
    access_recording = create_access_recording(parent_recording: folder_recording, user: create_user, role: :edit)
    grant = access_grant_for(access_recording, root_recording)
    registration = RecordingStudioApi::RecordableRegistration.new(
      recordable_type: "Folder",
      relationships: {
        "related" => {
          source: :custom,
          many: true,
          include: :request,
          limit: 10,
          serializer: ->(recordable, **) { { name: recordable.name } },
          output_keys: ["name"],
          resolver: ->(_context) { [visible, sibling, other_root] }
        }
      }
    )

    RecordingStudioApi.stub(:recordable_registration_for, ->(*, **) { registration }) do
      context = RecordingStudioApi::RelationshipContext.for(
        recordings: [folder_recording],
        include_values: "related",
        scoped_recordings: grant.accessible_recordings,
        api_key: :public,
        api_version: "v1",
        access_grant: grant,
        batch: false
      )
      resolved = context.relationship_value(folder_recording, "related")

      assert_equal [visible], resolved
    end
  end

  test "membership checks do not materialize the id list" do
    root_recording, access_recording = create_access_recording_for(user: @user, role: :edit)
    page_recording = create_page_recording(root_recording: root_recording)
    other_root, = create_access_recording_for(user: @user, role: :edit, workspace_name: "Other Workspace")
    other_page = create_page_recording(root_recording: other_root)
    grant = access_grant_for(access_recording, root_recording)

    assert grant.accessible_recordings.exists?(id: page_recording.id)
    refute grant.accessible_recordings.exists?(id: other_page.id)
    refute grant.accessible_recordings.exists?(id: nil)
  end

  private

  def access_grant_for(access_recording, root_recording)
    RecordingStudioApi::AccessGrant.new(
      api_client: nil,
      credential: nil,
      access_recording: access_recording,
      root_recording: root_recording
    )
  end

  def capture_sql(&)
    queries = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s
      next if payload[:name] == "SCHEMA"
      next if sql.match?(/\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)

      queries << sql.squish
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record", &)
    queries
  end
end
