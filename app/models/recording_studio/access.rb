# frozen_string_literal: true

module RecordingStudio
  class Access < ApplicationRecord
    self.table_name = "recording_studio_accesses"

    include RecordingStudio::Recordable

    belongs_to :actor, polymorphic: true

    enum :role, { view: 0, edit: 1, admin: 2 }
  end
end
