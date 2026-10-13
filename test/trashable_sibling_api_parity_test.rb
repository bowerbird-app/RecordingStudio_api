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
    remove_recording_default_scope!
  end

  test "query helpers expose kept sql and predicates without lifecycle methods" do
    assert defined?(RecordingStudioTrashable)
    assert_equal "0.10.0", RecordingStudioTrashable::VERSION
    refute defined?(RecordingStudioTrashable::Engine)

    recording = RecordingStudio::Recording
    assert_respond_to recording, :recording_studio_trashable_kept_sql
    assert_respond_to recording, :recording_studio_trashable_active

    connection = recording.connection
    child_kept = "#{connection.quote_table_name('child')}.#{connection.quote_column_name('trashed_at')} IS NULL"
    assert_equal child_kept, recording.recording_studio_trashable_kept_sql("child")

    root_recording, = create_access_recording_for(user: @user, role: :edit)
    page = create_page_recording(root_recording: root_recording)
    assert_predicate page, :recording_studio_trashable_kept?

    refute_respond_to page, :recording_studio_trashable_trash!
    refute_respond_to page, :recording_studio_trashable_restore!
    refute_respond_to page, :recording_studio_trashable_purge!
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

  test "actor access lookup and oauth exists use kept_sql under hostile default_scope" do
    root_recording, access_recording = create_access_recording_for(user: @user, role: :admin)
    install_hostile_recording_default_scope!

    kept_ids = RecordingStudioApi.actor_access_recordings(actor: @user).map(&:id).sort
    main_ids = RecordingStudio::Recording.unscoped
                                         .where(
                                           recordable_type: "RecordingStudio::Access",
                                           recordable_id: RecordingStudio::Access.where(actor: @user).select(:id)
                                         )
                                         .where(RecordingStudio::Recording.recording_studio_trashable_kept_sql)
                                         .pluck(:id)
                                         .sort
    assert_equal main_ids, kept_ids
    assert_includes kept_ids, access_recording.id

    access_recording.update_column(:trashed_at, Time.current)
    after_trash = RecordingStudioApi.actor_access_recordings(actor: @user).map(&:id)
    refute_includes after_trash, access_recording.id

    oauth = RecordingStudioApi::Services::AuthenticateOauthAccessToken
            .new(authorization_header: "Bearer unused", api: :public)
    refute oauth.send(
      :active_recording_exists_for?,
      access_recording.recordable_type,
      access_recording.recordable_id
    )
    assert_equal root_recording.id, access_recording.root_recording_id
  end

  test "production call sites keep additive kept_sql under where.not default_scope" do
    root_recording, access_recording = create_access_recording_for(user: @user, role: :admin)
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

    install_hostile_recording_default_scope!

    # Prior only-trashed relation: active would unscope and return kept siblings;
    # kept_sql (and main's where(trashed_at: nil)) stay empty.
    only_trashed = RecordingStudio::Recording
                   .unscope(where: :trashed_at)
                   .where(parent_recording_id: folder_recording.id)
                   .where.not(trashed_at: nil)
    main_style = only_trashed.where(trashed_at: nil).pluck(:id).sort
    kept_sql_style = only_trashed.where(RecordingStudio::Recording.recording_studio_trashable_kept_sql).pluck(:id).sort
    active_style = only_trashed.recording_studio_trashable_active.pluck(:id).sort

    assert_equal main_style, kept_sql_style
    assert_empty kept_sql_style
    refute_equal main_style, active_style
    assert_includes active_style, kept_page.id

    # Integration actor lookup (real call site) matches additive kept_sql.
    access_recording.update_column(:trashed_at, Time.current)
    actor_ids = RecordingStudioApi.actor_access_recordings(actor: @user).map(&:id).sort
    expected = RecordingStudio::Recording.unscoped
                                         .where(
                                           recordable_type: "RecordingStudio::Access",
                                           recordable_id: RecordingStudio::Access.where(actor: @user).select(:id)
                                         )
                                         .where(RecordingStudio::Recording.recording_studio_trashable_kept_sql)
                                         .pluck(:id)
                                         .sort
    assert_equal expected, actor_ids
    refute_includes actor_ids, access_recording.id

    # Access-management policy access recordings (real call site).
    policy = RecordingStudioApi::AccessManagementPolicy.new(actor: @user)
    policy_ids = policy.send(:access_recordings).map(&:id).sort
    assert_equal expected, policy_ids

    # Admin clients query root type filter (real call site shape).
    context = Object.new
    context.define_singleton_method(:current_actor) { @user }
    context.define_singleton_method(:params) { { "root_type" => "Workspace" } }
    context.define_singleton_method(:root_recording) { root_recording }
    query = RecordingStudioApi::Admin::Queries::ApiAccessClientsQuery.new(context)
    root_scope = query.send(:root_recordings_for_type)
    refute_includes root_scope.pluck(:id), trashed_page.id
    assert_includes root_scope.to_sql, RecordingStudio::Recording.recording_studio_trashable_kept_sql
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

  private

  def install_hostile_recording_default_scope!
    recording_class = RecordingStudio::Recording
    @previous_default_scopes = recording_class.default_scopes.dup
    recording_class.class_eval do
      default_scope { where.not(trashed_at: nil) }
    end
  end

  def remove_recording_default_scope!
    return if @previous_default_scopes.nil?

    RecordingStudio::Recording.default_scopes = @previous_default_scopes
    @previous_default_scopes = nil
  end
end
