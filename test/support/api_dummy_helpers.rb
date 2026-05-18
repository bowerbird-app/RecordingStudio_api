# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "../test_helper"
require_relative "../dummy/config/environment"
require "rails/test_help"

module ApiDummyHelpers
  TEST_PASSWORD = "ApiAuthPassword!2026"

  def reset_recording_studio_api_configuration!
    RecordingStudioApi.instance_variable_set(:@configuration, RecordingStudioApi::Configuration.new)
  end

  def reset_recording_studio_capabilities!
    configuration = RecordingStudio.configuration
    configuration.instance_variable_set(:@capabilities, {})
    configuration.instance_variable_set(:@capability_options, {})
  end

  def create_user(email: "api-user-#{SecureRandom.hex(4)}@example.com")
    User.find_or_create_by!(email: email) do |user|
      user.password = TEST_PASSWORD
      user.password_confirmation = TEST_PASSWORD
    end
  end

  def create_access_recording_for(user:, workspace_name: "Workspace #{SecureRandom.hex(4)}", role: :admin)
    Current.actor = user
    workspace = Workspace.create!(name: workspace_name)
    root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    access = RecordingStudio::Access.create!(actor: user, role: role)
    access_recording = RecordingStudio::Recording.create!(recordable: access, parent_recording: root_recording)

    [root_recording, access_recording]
  end

  def create_access_recording_under_boundary_for(user:, workspace_name: "Workspace #{SecureRandom.hex(4)}",
                                                 role: :admin, minimum_role: :edit)
    Current.actor = user
    workspace = Workspace.create!(name: workspace_name)
    root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    boundary = RecordingStudio::AccessBoundary.create!(minimum_role: minimum_role)
    boundary_recording = RecordingStudio::Recording.create!(recordable: boundary, parent_recording: root_recording)
    access = RecordingStudio::Access.create!(actor: user, role: role)
    access_recording = RecordingStudio::Recording.create!(recordable: access, parent_recording: boundary_recording)

    [root_recording, boundary_recording, access_recording]
  end

  def create_access_boundary_recording(parent_recording:, minimum_role: :edit)
    boundary = RecordingStudio::AccessBoundary.create!(minimum_role: minimum_role)

    RecordingStudio::Recording.create!(
      recordable: boundary,
      parent_recording: parent_recording
    )
  end

  def create_page_recording(root_recording:, parent_recording: nil, folder_name: "Folder #{SecureRandom.hex(4)}", page_title: "Page #{SecureRandom.hex(4)}")
    parent_recording ||= root_recording
    folder = Folder.create!(name: folder_name)
    folder_recording = RecordingStudio::Recording.create!(recordable: folder, parent_recording: parent_recording)
    page = Page.create!(title: page_title)

    RecordingStudio::Recording.create!(recordable: page, parent_recording: folder_recording)
  end
end
