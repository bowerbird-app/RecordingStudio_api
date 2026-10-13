# frozen_string_literal: true

require_relative "support/api_dummy_helpers"

class TrashableSiblingApiParityTest < ActiveSupport::TestCase
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

  test "Recording exposes Trashable sibling keep and trash helpers" do
    assert defined?(RecordingStudioTrashable)
    assert_equal RecordingStudioTrashable::VERSION, "0.9.0"

    recording = RecordingStudio::Recording
    assert_respond_to recording, :recording_studio_trashable_active
    assert_respond_to recording, :recording_studio_trashable_kept_sql
    assert_respond_to recording, :recording_studio_trashable_trashed_sql

    connection = recording.connection
    child_kept = "#{connection.quote_table_name('child')}.#{connection.quote_column_name('trashed_at')} IS NULL"
    child_trashed = "#{connection.quote_table_name('child')}.#{connection.quote_column_name('trashed_at')} IS NOT NULL"

    assert_equal child_kept, recording.recording_studio_trashable_kept_sql("child")
    assert_equal child_trashed, recording.recording_studio_trashable_trashed_sql("child")
  end

  test "kept and trashed predicates match raw trashed_at presence" do
    root_recording, = create_access_recording_for(user: @user, role: :edit)
    page_recording = create_page_recording(root_recording: root_recording)

    assert page_recording.recording_studio_trashable_kept?
    refute page_recording.recording_studio_trashable_trashed?

    page_recording.update_column(:trashed_at, Time.current)
    page_recording.reload

    refute page_recording.recording_studio_trashable_kept?
    assert page_recording.recording_studio_trashable_trashed?
    assert_equal page_recording.trashed_at.present?, page_recording.recording_studio_trashable_trashed?
    assert_equal page_recording.trashed_at.nil?, page_recording.recording_studio_trashable_kept?
  end

  test "accessible recording scope SQL uses kept_sql for child filter" do
    root_recording, access_recording = create_access_recording_for(user: @user, role: :edit)
    scope = RecordingStudioApi::AccessibleRecordingScope.new(
      scope_recording: root_recording,
      access_recording: access_recording
    )

    sql = scope.send(:accessible_recording_ids_sql)
    kept_sql = RecordingStudio::Recording.recording_studio_trashable_kept_sql("child")

    assert_includes sql, "WHERE #{kept_sql}"
    refute_includes sql, "WHERE child.trashed_at IS NULL"
  end

  test "actor access lookup excludes trashed recordings with additive kept filter" do
    root_recording, access_recording = create_access_recording_for(user: @user, role: :edit)
    kept = RecordingStudioApi.actor_access_recordings(actor: @user)
    assert_includes kept.map(&:id), access_recording.id

    access_recording.update_column(:trashed_at, Time.current)
    trashed = RecordingStudioApi.actor_access_recordings(actor: @user)

    refute_includes trashed.map(&:id), access_recording.id
    assert_equal root_recording.id, access_recording.root_recording_id
  end

  test "additive kept filter matches main under a trashed_at default_scope" do
    root_recording, access_recording = create_access_recording_for(user: @user, role: :edit)
    folder = Folder.create!(name: "Parity folder")
    folder_recording = RecordingStudio::Recording.create!(recordable: folder, parent_recording: root_recording)
    kept_page = RecordingStudio::Recording.create!(
      recordable: Page.create!(title: "Kept page"),
      parent_recording: folder_recording
    )
    trashed_page = RecordingStudio::Recording.create!(
      recordable: Page.create!(title: "Trashed page"),
      parent_recording: folder_recording
    )
    trashed_page.update_column(:trashed_at, Time.current)

    recording_class = RecordingStudio::Recording
    previous_default_scopes = recording_class.default_scopes.dup
    recording_class.class_eval do
      default_scope { where(trashed_at: nil) }
    end

    begin
      only_trashed = recording_class
                     .unscope(where: :trashed_at)
                     .where(parent_recording_id: folder_recording.id)
                     .where.not(trashed_at: nil)

      main_style_ids = only_trashed.where(trashed_at: nil).pluck(:id).sort
      active_scope_ids = only_trashed.recording_studio_trashable_active.pluck(:id).sort

      # active unscopes first, so it returns kept siblings main would exclude.
      assert_empty main_style_ids
      refute_equal main_style_ids, active_scope_ids
      assert_includes active_scope_ids, kept_page.id
      refute_includes active_scope_ids, trashed_page.id

      # Production actor lookup stays on main's additive filter under the default_scope.
      access_recording.update_column(:trashed_at, Time.current)
      actor_ids = RecordingStudioApi.actor_access_recordings(actor: @user).map(&:id).sort
      main_actor_ids = recording_class.unscoped
                                      .where(
                                        recordable_type: "RecordingStudio::Access",
                                        recordable_id: RecordingStudio::Access.where(actor: @user).select(:id),
                                        trashed_at: nil
                                      )
                                      .pluck(:id)
                                      .sort

      assert_equal main_actor_ids, actor_ids
      refute_includes actor_ids, access_recording.id

      oauth_exists = RecordingStudioApi::Services::AuthenticateOauthAccessToken
                     .new(authorization_header: "Bearer unused", api: :public)
                     .send(
                       :active_recording_exists_for?,
                       trashed_page.recordable_type,
                       trashed_page.recordable_id
                     )
      refute oauth_exists
      refute recording_class.unscoped.exists?(id: trashed_page.id, trashed_at: nil)
    ensure
      recording_class.default_scopes = previous_default_scopes
    end
  end

  test "credential authentication rejects trashed access via kept predicate" do
    root_recording, access_recording = create_access_recording_for(user: @user, role: :admin)
    result = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: access_recording,
      name: "Parity client"
    )
    assert result.success?, result.error
    credential = result.value.fetch(:credential)
    client_access = credential.effective_access_recording

    assert_predicate credential, :active_for_authentication?
    assert_predicate client_access, :recording_studio_trashable_kept?

    client_access.update_column(:trashed_at, Time.current)
    credential.instance_variable_set(:@effective_access_recording, nil)

    refute_predicate credential, :active_for_authentication?
    assert_equal root_recording.id, access_recording.root_recording_id
  end

  test "admin client query SQL uses kept_sql fragments" do
    recordings_table = RecordingStudio::Recording.table_name
    kept_for_table = RecordingStudio::Recording.recording_studio_trashable_kept_sql(recordings_table)
    kept_for_child = RecordingStudio::Recording.recording_studio_trashable_kept_sql("child")
    actor = @user

    context = Object.new
    context.define_singleton_method(:current_actor) { actor }
    context.define_singleton_method(:params) { {} }
    query = RecordingStudioApi::Admin::Queries::ApiAccessClientsQuery.new(context)

    access_point_sql = query.send(:accessible_access_point_ids_sql)
    assert_includes access_point_sql, kept_for_table
    assert_includes access_point_sql, kept_for_child
    refute_includes access_point_sql, "#{recordings_table}.trashed_at IS NULL"
    refute_includes access_point_sql, "child.trashed_at IS NULL"

    root_recording, = create_access_recording_for(user: @user)
    scoped_sql = query.send(:scoped_recording_ids_sql, root_recording)
    assert_includes scoped_sql, kept_for_child
    refute_includes scoped_sql, "child.trashed_at IS NULL"
  end

  test "void_recording soft-voids a single row without trash_root" do
    root_recording, = create_access_recording_for(user: @user, role: :edit)
    page_recording = create_page_recording(root_recording: root_recording)
    time = Time.zone.parse("2026-10-13 12:00:00 UTC")

    result = RecordingStudioTrashable.void_recording!(page_recording, time: time)
    page_recording.reload

    assert_same page_recording, result
    assert page_recording.recording_studio_trashable_trashed?
    assert_in_delta time.to_i, page_recording.trashed_at.to_i, 1
    assert_equal false, page_recording.read_attribute(:trash_root) if page_recording.has_attribute?(:trash_root)
  end
end
