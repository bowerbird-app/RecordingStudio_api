# frozen_string_literal: true

class Workspace < ApplicationRecord
  include RecordingStudioAdmin::AllowsAdminSections

  recording_studio_recordable(
    label: "Workspace",
    plural_label: "Workspaces",
    root: true,
    allowed_parent_types: ["Workspace", "Folder"]
  )

  recording_studio_admin_sections do
    section :api
  end
end
