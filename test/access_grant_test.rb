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
end
