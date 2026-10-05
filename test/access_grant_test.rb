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

  test "unknown required role is not authorized" do
    root_recording, access_recording = create_access_recording_for(user: @user, role: :admin)
    page_recording = create_page_recording(root_recording: root_recording)
    grant = access_grant_for(access_recording: access_recording, root_recording: root_recording)

    refute grant.authorized?(recording: page_recording, role: :owner)
  end

  private

  def access_grant_for(access_recording:, root_recording:)
    RecordingStudioApi::AccessGrant.new(
      api_client: nil,
      credential: nil,
      access_recording: access_recording,
      root_recording: root_recording
    )
  end
end
