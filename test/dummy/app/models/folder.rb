# frozen_string_literal: true

class Folder < ApplicationRecord
  include RecordingStudioAdmin::AllowsAdminSections

  recording_studio_recordable(
    label: "Folder",
    plural_label: "Folders",
    root: true,
    allowed_parent_types: ["Workspace", "Folder"]
  )

  recording_studio_admin_sections do
    section :api
  end
end
