# frozen_string_literal: true

module RecordingStudio
  class AccessBoundary < ApplicationRecord
    self.table_name = "recording_studio_access_boundaries"

    include RecordingStudio::Recordable

    enum :minimum_role, { view: 0, edit: 1, admin: 2 }
  end
end
