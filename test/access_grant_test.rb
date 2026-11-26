# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "test_helper"
require_relative "dummy/config/environment"
require_relative "support/api_dummy_helpers"

class AccessGrantTest < ActiveSupport::TestCase
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

  test "view grant authorizes view and not edit" do
    root_recording, access_recording = create_access_recording_for(user: @user, role: :view)
    page_recording = create_page_recording(root_recording: root_recording)
    grant = access_grant_for(access_recording: access_recording, root_recording: root_recording)

    assert grant.authorized?(recording: page_recording, role: :view)
    refute grant.authorized?(recording: page_recording, role: :edit)
  end

  test "edit grant authorizes edit and not admin" do
    root_recording, access_recording = create_access_recording_for(user: @user, role: :edit)
    page_recording = create_page_recording(root_recording: root_recording)
    grant = access_grant_for(access_recording: access_recording, root_recording: root_recording)

    assert grant.authorized?(recording: page_recording, role: :edit)
    refute grant.authorized?(recording: page_recording, role: :admin)
  end

  test "admin grant authorizes admin" do
    root_recording, access_recording = create_access_recording_for(user: @user, role: :admin)
    page_recording = create_page_recording(root_recording: root_recording)
    grant = access_grant_for(access_recording: access_recording, root_recording: root_recording)

    assert grant.authorized?(recording: page_recording, role: :admin)
  end

  test "Access does not expose a roles enum map" do
    refute RecordingStudio::Access.respond_to?(:roles)
  end

  test "Access is Accessible's model and rejects a direct create" do
    model_path = File.expand_path("../app/models/recording_studio/access.rb", __dir__)

    refute File.exist?(model_path)
    assert_includes RecordingStudio::Access.included_modules, RecordingStudioAccessible::AccessCreationGuard

    error = assert_raises(ActiveRecord::RecordInvalid) do
      RecordingStudio::Access.create!(actor: @user, role: :view)
    end

    assert_match(/grant_access/, error.message)
  end

  test "unknown required role is not authorized" do
    root_recording, access_recording = create_access_recording_for(user: @user, role: :admin)
    page_recording = create_page_recording(root_recording: root_recording)
    grant = access_grant_for(access_recording: access_recording, root_recording: root_recording)

    refute grant.authorized?(recording: page_recording, role: :owner)
  end

  test "a trashed recording uses role_for on that recording" do
    root_recording, access_recording = create_access_recording_for(user: @user, role: :edit)
    page_recording = trash!(page_under(root_recording))
    grant = access_grant_for(access_recording: access_recording, root_recording: root_recording)

    assert_equal false, page_recording.kept?
    assert_equal :edit, RecordingStudioAccessible.role_for(actor: @user, recording: page_recording)
    refute grant.authorized?(recording: page_recording, role: :view, include_trashed: false)
    assert grant.authorized?(recording: page_recording, role: :view, include_trashed: true)
    assert grant.authorized?(recording: page_recording, role: :edit, include_trashed: true)
    refute grant.authorized?(recording: page_recording, role: :admin, include_trashed: true)
    refute grant.authorized?(recording: nil, role: :view, include_trashed: true)
  end

  test "a direct grant on a trashed recording is not replaced by the parent role" do
    root_recording, = create_access_recording_for(user: @user, role: :view)
    page_recording = page_under(root_recording)
    page_access = with_access_creation_context do
      access = RecordingStudio::Access.create!(actor: @user, role: :admin)
      RecordingStudio::Recording.create!(recordable: access, parent_recording: page_recording)
    end
    trash!(page_recording)
    grant = access_grant_for(access_recording: page_access, root_recording: root_recording)

    assert_equal :view, RecordingStudioAccessible.role_for(actor: @user, recording: page_recording.parent_recording)
    assert_equal :admin, RecordingStudioAccessible.role_for(actor: @user, recording: page_recording)
    assert grant.authorized?(recording: page_recording, role: :admin, include_trashed: true)
    refute grant.authorized?(recording: page_recording, role: :admin, include_trashed: false)
  end

  test "a grant several levels up authorizes a trashed descendant through a trashed ancestor" do
    root_recording, access_recording = create_access_recording_for(user: @user, role: :edit)
    folder = nested_folder_recording("Level one", root_recording)
    middle = trash!(nested_folder_recording("Level two", folder))
    page_recording = trash!(page_under(middle))
    grant = access_grant_for(access_recording: access_recording, root_recording: root_recording)
    outsider = create_user(email: "grant-outsider-#{SecureRandom.hex(4)}@example.com")

    assert_equal :edit, RecordingStudioAccessible.role_for(actor: @user, recording: page_recording)
    assert_nil RecordingStudioAccessible.role_for(actor: outsider, recording: page_recording)
    assert grant.authorized?(recording: page_recording, role: :edit, include_trashed: true)
    refute grant.authorized?(recording: page_recording, role: :admin, include_trashed: true)
    refute grant.authorized?(recording: page_recording, role: :view, include_trashed: false)
  end

  test "a delegated view user cannot take an edit from the app grant" do
    manager = create_user(email: "delegated-manager-#{SecureRandom.hex(4)}@example.com")
    root_recording, = create_access_recording_for(user: manager, role: :admin)
    viewer = create_user(email: "delegated-viewer-#{SecureRandom.hex(4)}@example.com")
    grant_or_bootstrap_access!(recording: root_recording, actor: viewer, role: :view)
    page_recording = create_page_recording(root_recording: root_recording)
    app = RecordingStudioApi::ApiClient.create!(name: "Delegated app", api_key: "public", owner: manager)
    app_access = grant_or_bootstrap_access!(recording: root_recording, actor: app, role: :admin)
    grant = delegated_grant_for(
      app: app,
      access_recording: app_access,
      root_recording: root_recording,
      authorized_by: viewer
    )

    assert_equal viewer, grant.actor
    assert_equal viewer, grant.owner
    assert_equal :admin, RecordingStudioAccessible.role_for(actor: manager, recording: page_recording)
    assert_equal :admin, RecordingStudioAccessible.role_for(actor: app, recording: page_recording)
    assert_equal :view, RecordingStudioAccessible.role_for(actor: viewer, recording: page_recording)
    assert grant.authorized?(recording: page_recording, role: :view)
    refute grant.authorized?(recording: page_recording, role: :edit)
    error = assert_raises(RecordingStudioApi::AuthorizationError) do
      grant.authorize!(recording: page_recording, role: :edit)
    end
    assert_equal RecordingStudioApi::AuthorizationError.for_required_role(:edit), error.message
  end

  test "a delegated edit user cannot take admin from the app grant" do
    manager = create_user(email: "delegated-edit-manager-#{SecureRandom.hex(4)}@example.com")
    root_recording, = create_access_recording_for(user: manager, role: :admin)
    editor = create_user(email: "delegated-editor-#{SecureRandom.hex(4)}@example.com")
    grant_or_bootstrap_access!(recording: root_recording, actor: editor, role: :edit)
    page_recording = create_page_recording(root_recording: root_recording)
    app = RecordingStudioApi::ApiClient.create!(name: "Delegated edit app", api_key: "public", owner: manager)
    app_access = grant_or_bootstrap_access!(recording: root_recording, actor: app, role: :admin)
    grant = delegated_grant_for(
      app: app,
      access_recording: app_access,
      root_recording: root_recording,
      authorized_by: editor
    )

    assert grant.authorized?(recording: page_recording, role: :edit)
    refute grant.authorized?(recording: page_recording, role: :admin)
    error = assert_raises(RecordingStudioApi::AuthorizationError) do
      grant.authorize!(recording: page_recording, role: :admin)
    end
    assert_equal RecordingStudioApi::AuthorizationError.for_required_role(:admin), error.message
  end

  test "a delegated admin user keeps admin when the app grant is admin" do
    manager = create_user(email: "delegated-admin-manager-#{SecureRandom.hex(4)}@example.com")
    root_recording, = create_access_recording_for(user: manager, role: :admin)
    page_recording = create_page_recording(root_recording: root_recording)
    app = RecordingStudioApi::ApiClient.create!(name: "Delegated admin app", api_key: "public", owner: manager)
    app_access = grant_or_bootstrap_access!(recording: root_recording, actor: app, role: :admin)
    grant = delegated_grant_for(
      app: app,
      access_recording: app_access,
      root_recording: root_recording,
      authorized_by: manager
    )

    assert_equal manager, grant.actor
    assert grant.authorized?(recording: page_recording, role: :admin)
  end

  test "a delegated token still cannot exceed its consented grant role" do
    manager = create_user(email: "delegated-scope-manager-#{SecureRandom.hex(4)}@example.com")
    root_recording, = create_access_recording_for(user: manager, role: :admin)
    page_recording = create_page_recording(root_recording: root_recording)
    app = RecordingStudioApi::ApiClient.create!(name: "View-consented app", api_key: "public", owner: manager)
    app_access = grant_or_bootstrap_access!(recording: root_recording, actor: app, role: :view)
    grant = delegated_grant_for(
      app: app,
      access_recording: app_access,
      root_recording: root_recording,
      authorized_by: manager
    )

    assert grant.authorized?(recording: page_recording, role: :view)
    refute grant.authorized?(recording: page_recording, role: :edit)
  end

  test "client credentials still use the client owner when authorized_by is absent" do
    manager = create_user(email: "cc-manager-#{SecureRandom.hex(4)}@example.com")
    root_recording, = create_access_recording_for(user: manager, role: :admin)
    page_recording = create_page_recording(root_recording: root_recording)
    app = RecordingStudioApi::ApiClient.create!(name: "Machine client", api_key: "public", owner: manager)
    app_access = grant_or_bootstrap_access!(recording: root_recording, actor: app, role: :edit)
    grant = RecordingStudioApi::AccessGrant.new(
      api_client: app,
      credential: nil,
      access_recording: app_access,
      root_recording: root_recording
    )

    assert_nil grant.authorized_by
    assert_equal app, grant.actor
    assert_equal manager, grant.owner
    assert grant.authorized?(recording: page_recording, role: :edit)
    refute grant.authorized?(recording: page_recording, role: :admin)
  end

  test "a trashed grant and a recording in another tree are denied" do
    root_recording, access_recording = create_access_recording_for(user: @user, role: :admin)
    page_recording = trash!(page_under(root_recording))
    access_recording.update_column(:trashed_at, Time.current)
    grant = access_grant_for(access_recording: access_recording, root_recording: root_recording)

    assert_nil RecordingStudioAccessible.role_for(actor: @user, recording: page_recording)
    refute grant.authorized?(recording: page_recording, role: :view, include_trashed: true)

    other_root, = create_access_recording_for(user: create_user, role: :admin)
    other_page = page_under(other_root)
    fresh_root, fresh_access = create_access_recording_for(user: @user, role: :admin)
    fresh_grant = access_grant_for(access_recording: fresh_access, root_recording: fresh_root)

    assert_nil RecordingStudioAccessible.role_for(actor: @user, recording: other_page)
    refute fresh_grant.authorized?(recording: other_page, role: :view, include_trashed: true)
  end

  private

  def page_under(parent)
    RecordingStudio::Recording.create!(
      recordable: Page.create!(title: "Page #{SecureRandom.hex(4)}"),
      parent_recording: parent
    )
  end

  def trash!(recording)
    recording.update_column(:trashed_at, Time.current)
    recording.reload
  end

  def access_grant_for(access_recording:, root_recording:)
    RecordingStudioApi::AccessGrant.new(
      api_client: nil,
      credential: nil,
      access_recording: access_recording,
      root_recording: root_recording
    )
  end

  def delegated_grant_for(app:, access_recording:, root_recording:, authorized_by:)
    RecordingStudioApi::AccessGrant.new(
      api_client: app,
      credential: nil,
      access_recording: access_recording,
      root_recording: root_recording,
      authorized_by: authorized_by
    )
  end
end
