# frozen_string_literal: true

class Page < ApplicationRecord
  recording_studio_recordable(
    label: "Page",
    plural_label: "Pages",
    root: false,
    allowed_parent_types: ["Workspace", "Folder"]
  )

  validates :title, presence: true
end
