# frozen_string_literal: true

# This migration comes from recording_studio_trashable (originally 20250101000004)
class AddPurgeAtToRecordingStudioRecordings < ActiveRecord::Migration[8.1]
  INDEX_NAME = "idx_rs_recordings_due_purge_at"
  DUE_INDEX_WHERE = "trashed_at IS NOT NULL"

  def up
    return unless table_exists?(:recording_studio_recordings)

    unless column_exists?(:recording_studio_recordings, :purge_at)
      add_column :recording_studio_recordings, :purge_at, :datetime
    end

    return if index_exists?(:recording_studio_recordings, :purge_at, name: INDEX_NAME)

    add_index :recording_studio_recordings, :purge_at, name: INDEX_NAME, where: DUE_INDEX_WHERE
  end

  def down
    return unless table_exists?(:recording_studio_recordings)

    if index_exists?(:recording_studio_recordings, :purge_at, name: INDEX_NAME)
      remove_index :recording_studio_recordings, name: INDEX_NAME
    end

    return unless column_exists?(:recording_studio_recordings, :purge_at)

    remove_column :recording_studio_recordings, :purge_at
  end
end
