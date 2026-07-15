# frozen_string_literal: true

class AdminSection < ApplicationRecord
  include RecordingStudio::Recordable
  include RecordingStudioAccessible::AllowsAccessibleChildren

  recording_studio_recordable label: "Admin section", root: false, allowed_parent_types: ["AdminRoot"]
  recording_studio_accessible_children :access
end