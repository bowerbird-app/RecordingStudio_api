# frozen_string_literal: true

module RecordingStudioApi
  class AdminApi < ApplicationRecord
    self.table_name = "recording_studio_api_admin_apis"

    recording_studio_recordable(
      label: "Admin API",
      plural_label: "Admin APIs",
      root: false,
      allowed_parent_types: ["RecordingStudioAdmin::Admin"]
    )

    validates :key, presence: true, uniqueness: true
    validates :name, presence: true
  end
end