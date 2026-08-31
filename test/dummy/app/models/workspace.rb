# frozen_string_literal: true

class Workspace < ApplicationRecord
  include RecordingStudioAdmin::AllowsAdminSections

  recording_studio_recordable(
    label: "Workspace",
    plural_label: "Workspaces",
    root: true,
    shared: false,
    allowed_parent_types: ["Workspace", "Folder"]
  )
  RecordingStudio.enable_capability(:accessible, on: self)
  RecordingStudio.enable_capability(:api_access_point, on: self)

  recording_studio_admin_sections do
    section :api
  end
end
