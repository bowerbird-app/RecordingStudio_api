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
end
