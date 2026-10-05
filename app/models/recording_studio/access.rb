# frozen_string_literal: true

module RecordingStudio
  class Access < ApplicationRecord
    self.table_name = "recording_studio_accesses"

    include RecordingStudio::Recordable

    recording_studio_recordable(
      label: "Access",
      plural_label: "Access",
      root: false,
      allowed_parent_types: []
    )

    belongs_to :actor, polymorphic: true
  end
end
