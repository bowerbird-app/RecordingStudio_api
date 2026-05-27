# frozen_string_literal: true

module RecordingStudioApi
  class AdminApi < ApplicationRecord
    self.table_name = "recording_studio_api_admin_apis"

    validates :key, presence: true, uniqueness: true
    validates :name, presence: true
  end
end