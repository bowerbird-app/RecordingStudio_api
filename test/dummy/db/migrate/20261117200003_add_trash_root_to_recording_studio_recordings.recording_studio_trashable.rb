# frozen_string_literal: true

# This migration comes from recording_studio_trashable (originally 20250101000003)
class AddTrashRootToRecordingStudioRecordings < ActiveRecord::Migration[8.1]
  INDEX_NAME = "idx_rs_recordings_trashed_at_trash_root"
  BACKFILL_TRASH_ROOTS_SQL = <<~SQL.squish
    UPDATE recording_studio_recordings AS recordings
    SET trash_root = CASE
      WHEN recordings.trashed_at IS NULL THEN FALSE
      WHEN EXISTS (
        SELECT 1
        FROM recording_studio_recordings AS parents
        WHERE parents.id = recordings.parent_recording_id
          AND parents.trashed_at IS NOT NULL
      ) THEN FALSE
      ELSE TRUE
    END
  SQL

  def up
    return unless table_exists?(:recording_studio_recordings)

    unless column_exists?(:recording_studio_recordings, :trash_root)
      add_column :recording_studio_recordings, :trash_root, :boolean, default: false, null: false
    end

    unless index_exists?(:recording_studio_recordings, %i[trashed_at trash_root], name: INDEX_NAME)
      add_index :recording_studio_recordings, %i[trashed_at trash_root], name: INDEX_NAME
    end

    backfill_trash_roots
  end

  def down
    return unless table_exists?(:recording_studio_recordings)

    if index_exists?(:recording_studio_recordings, %i[trashed_at trash_root], name: INDEX_NAME)
      remove_index :recording_studio_recordings, name: INDEX_NAME
    end

    remove_column :recording_studio_recordings, :trash_root if column_exists?(:recording_studio_recordings, :trash_root)
  end

  private

  def backfill_trash_roots
    execute(BACKFILL_TRASH_ROOTS_SQL)
  end
end
