# frozen_string_literal: true

class AddRecordingStudioRecordingsRootTypeCreationIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :recording_studio_recordings,
              %i[root_recording_id recordable_type created_at id],
              order: { created_at: :desc, id: :desc },
              name: "index_rs_recordings_on_root_type_created_at_id",
              if_not_exists: true
  end
end
