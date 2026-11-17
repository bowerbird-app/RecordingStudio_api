# frozen_string_literal: true

# This migration comes from recording_studio (originally 20261117200000).
class ReplaceRecordingStudioRecordingsRootIndex < ActiveRecord::Migration[8.1]
  NEW_INDEX = "index_rs_recordings_on_root_created_at_id"
  OLD_INDEX = "index_rs_recordings_on_root_recording"

  # Add the ordered index first so root_recording_id keeps a leading column
  # for the foreign key, then drop the single-column index.
  def up
    add_index :recording_studio_recordings,
              %i[root_recording_id created_at id],
              order: { created_at: :desc, id: :desc },
              name: NEW_INDEX,
              if_not_exists: true
    remove_index :recording_studio_recordings, name: OLD_INDEX, if_exists: true
  end

  def down
    add_index :recording_studio_recordings, :root_recording_id,
              name: OLD_INDEX,
              if_not_exists: true
    remove_index :recording_studio_recordings, name: NEW_INDEX, if_exists: true
  end
end