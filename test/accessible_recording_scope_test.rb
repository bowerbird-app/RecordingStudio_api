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

    ids = RecordingStudioApi::AccessibleRecordingScope.new(
      scope_recording: root_recording,
      access_recording: access_recording
    ).relation.pluck(:id)

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

    ids = RecordingStudioApi::AccessibleRecordingScope.new(
      scope_recording: root_recording,
      access_recording: access_recording
    ).relation.pluck(:id)

    assert_includes ids, folder_recording.id
    assert_not_includes ids, page_recording.id
  end

  test "can include trashed descendants when requested" do
    root_recording, access_recording = create_access_recording_for(user: @user, role: :admin)
    page_recording = create_page_recording(root_recording: root_recording)
    page_recording.update_column(:trashed_at, Time.current)

    ids = RecordingStudioApi::AccessibleRecordingScope.new(
      scope_recording: root_recording,
      access_recording: access_recording,
      include_trashed: true
    ).relation.pluck(:id)

    assert_includes ids, page_recording.id
  end

  test "memoizes recording ids for repeated authorization checks" do
    root_recording, access_recording = create_access_recording_for(user: @user, role: :edit)
    page_recording = create_page_recording(root_recording: root_recording)
    grant = RecordingStudioApi::AccessGrant.new(
      api_client: nil,
      credential: nil,
      access_recording: access_recording,
      root_recording: root_recording
    )

    first_ids = grant.accessible_recording_ids
    second_ids = grant.accessible_recording_ids

    assert_same first_ids, second_ids
    assert_includes first_ids, page_recording.id
    assert grant.accessible_recordings.exists?(id: page_recording.id)
  end

  test "returns empty relation when scope is nil" do
    root_recording, access_recording = create_access_recording_for(user: @user, role: :admin)

    relation = RecordingStudioApi::AccessibleRecordingScope.new(
      scope_recording: nil,
      access_recording: access_recording
    ).relation

    assert_empty relation.to_a
    assert_equal root_recording.id, access_recording.root_recording_id
  end

  test "returns empty relation when access recording is not a RecordingStudio::Access" do
    root_recording, = create_access_recording_for(user: @user, role: :admin)

    relation = RecordingStudioApi::AccessibleRecordingScope.new(
      scope_recording: root_recording,
      access_recording: root_recording
    ).relation

    assert_empty relation.to_a
  end

  test "accessible recordings stay a subquery and match accessible recording ids" do
    root_recording, access_recording = create_access_recording_for(user: @user, role: :edit)
    page_recording = create_page_recording(root_recording: root_recording)
    grant = access_grant_for(access_recording, root_recording)
    queries = capture_sql { grant.accessible_recordings.pluck(:id) }

    assert_equal 1, queries.length
    assert_includes queries.first, "scope_tree"
    refute_match(/IN \(\$\d+, \$\d+/, queries.first)
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

  test "hides a kept recording under a trashed folder" do
    root_recording, access_recording = create_access_recording_for(user: @user, role: :edit)
    folder = Folder.create!(name: "Trashed parent")
    folder_recording = RecordingStudio::Recording.create!(recordable: folder, parent_recording: root_recording)
    kept_page = create_page_recording(root_recording: root_recording, parent_recording: folder_recording)
    folder_recording.update_column(:trashed_at, Time.current)
    grant = access_grant_for(access_recording, root_recording)

    visible_ids = grant.accessible_recordings.pluck(:id)
    assert_not_includes visible_ids, folder_recording.id
    assert_not_includes visible_ids, kept_page.id
    assert_includes grant.accessible_recordings(include_trashed: true).pluck(:id), kept_page.id
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
    assert_equal visible_ids.sort, grant.accessible_recording_ids.sort
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

  test "include? checks membership without materializing the full id list" do
    root_recording, access_recording = create_access_recording_for(user: @user, role: :edit)
    page_recording = create_page_recording(root_recording: root_recording)
    other_root, = create_access_recording_for(user: @user, role: :edit, workspace_name: "Other Workspace")
    other_page = create_page_recording(root_recording: other_root)

    scope = RecordingStudioApi::AccessibleRecordingScope.new(
      scope_recording: root_recording,
      access_recording: access_recording
    )

    assert scope.include?(page_recording.id)
    refute scope.include?(other_page.id)
    refute scope.include?(nil)
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
