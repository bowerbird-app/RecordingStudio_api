# frozen_string_literal: true

module RecordingStudioApi
  class AdminApi < ApplicationRecord
    include RecordingStudio::Recordable

    self.table_name = "recording_studio_api_admin_apis"

    # No-op until a configured admin root class is loaded. Eager load must not
    # declare this against the default AdminRoot when the host has no such root.
    def self.declare_recordable!
      parent_types = RecordingStudioApi::Engine.admin_root_recordable_type_names
      return if parent_types.empty?

      recording_studio_recordable(
        label: "Admin API",
        plural_label: "Admin APIs",
        root: false,
        allowed_parent_types: parent_types
      )
    end

    declare_recordable!

    validates :key, presence: true, uniqueness: true
    validates :name, presence: true
  end
end