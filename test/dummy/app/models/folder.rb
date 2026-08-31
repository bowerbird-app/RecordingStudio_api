# frozen_string_literal: true

class Folder < ApplicationRecord
  include RecordingStudioAdmin::AllowsAdminSections

  recording_studio_recordable(
    label: "Folder",
    plural_label: "Folders",
    root: true,
    shared: false,
    allowed_parent_types: ["Workspace", "Folder"]
  )
  RecordingStudio.enable_capability(:accessible, on: self)
  RecordingStudio.enable_capability(:api_access_point, on: self)
  RecordingStudio.enable_capability(:movable, on: self)

  recording_studio_admin_sections do
    section :api
  end
end
