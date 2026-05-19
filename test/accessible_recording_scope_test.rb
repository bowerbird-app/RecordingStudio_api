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

  test "excludes stricter nested boundary subtree for lower role access" do
    root_recording, access_recording = create_access_recording_for(user: @user, role: :edit)
    visible_page = create_page_recording(root_recording: root_recording)

    restricted_boundary = RecordingStudio::AccessBoundary.create!(minimum_role: :admin)
    restricted_boundary_recording = RecordingStudio::Recording.create!(
      recordable: restricted_boundary,
      parent_recording: root_recording
    )
    hidden_page = create_page_recording(
      root_recording: root_recording,
      parent_recording: restricted_boundary_recording
    )

    ids = RecordingStudioApi::AccessibleRecordingScope.new(
      scope_recording: root_recording,
      access_recording: access_recording
    ).relation.pluck(:id)

    assert_includes ids, visible_page.id
    assert_not_includes ids, restricted_boundary_recording.id
    assert_not_includes ids, hidden_page.id
  end

  test "includes nested boundary subtree when role satisfies minimum" do
    root_recording, access_recording = create_access_recording_for(user: @user, role: :admin)

    restricted_boundary = RecordingStudio::AccessBoundary.create!(minimum_role: :admin)
    restricted_boundary_recording = RecordingStudio::Recording.create!(
      recordable: restricted_boundary,
      parent_recording: root_recording
    )
    page_recording = create_page_recording(
      root_recording: root_recording,
      parent_recording: restricted_boundary_recording
    )

    ids = RecordingStudioApi::AccessibleRecordingScope.new(
      scope_recording: root_recording,
      access_recording: access_recording
    ).relation.pluck(:id)

    assert_includes ids, restricted_boundary_recording.id
    assert_includes ids, page_recording.id
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
end
