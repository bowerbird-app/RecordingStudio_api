# frozen_string_literal: true

class Folder < ApplicationRecord
  recording_studio_recordable(
    label: "Folder",
    plural_label: "Folders",
    root: true,
    allowed_parent_types: ["Workspace", "Folder"]
  )
end
