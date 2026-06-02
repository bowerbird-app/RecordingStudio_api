# frozen_string_literal: true

class Workspace < ApplicationRecord
  recording_studio_recordable(
    label: "Workspace",
    plural_label: "Workspaces",
    root: true,
    allowed_parent_types: ["Workspace", "Folder"]
  )
end
