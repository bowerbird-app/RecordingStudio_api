# frozen_string_literal: true

# This migration comes from recording_studio_trashable (originally 20250101000001)
class AddTrashedAtToRecordingStudioRecordings < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:recording_studio_recordings, :trashed_at)
      add_column :recording_studio_recordings, :trashed_at, :datetime
    end

    return if index_exists?(:recording_studio_recordings, :trashed_at)

    add_index :recording_studio_recordings, :trashed_at
  end
end
