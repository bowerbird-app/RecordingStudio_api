# frozen_string_literal: true

class RemoveRecordingStudioAccessBoundaries < ActiveRecord::Migration[8.1]
  INDEX_NAME = "index_rs_unique_active_access_boundary_per_parent"
  BOUNDARY_TYPE = "RecordingStudio::AccessBoundary"

  def up
    remove_index :recording_studio_recordings, name: INDEX_NAME, if_exists: true

    if table_exists?(:recording_studio_recordings)
      execute <<~SQL.squish
        WITH RECURSIVE boundary_tree AS (
          SELECT id
          FROM recording_studio_recordings
          WHERE recordable_type = '#{BOUNDARY_TYPE}'

          UNION ALL

          SELECT child.id
          FROM recording_studio_recordings child
          INNER JOIN boundary_tree parent ON child.parent_recording_id = parent.id
        )
        DELETE FROM recording_studio_events
        WHERE recording_id IN (SELECT id FROM boundary_tree)
      SQL

      execute <<~SQL.squish
        WITH RECURSIVE boundary_tree AS (
          SELECT id
          FROM recording_studio_recordings
          WHERE recordable_type = '#{BOUNDARY_TYPE}'

          UNION ALL

          SELECT child.id
          FROM recording_studio_recordings child
          INNER JOIN boundary_tree parent ON child.parent_recording_id = parent.id
        )
        DELETE FROM recording_studio_recordings
        WHERE id IN (SELECT id FROM boundary_tree)
      SQL
    end

    drop_table :recording_studio_access_boundaries, if_exists: true
  end

  def down
    create_table :recording_studio_access_boundaries, id: :uuid, if_not_exists: true do |t|
      t.integer :minimum_role
      t.datetime :created_at, null: false
    end

    add_index :recording_studio_recordings,
              :parent_recording_id,
              unique: true,
              name: INDEX_NAME,
              where: "recordable_type = '#{BOUNDARY_TYPE}' AND trashed_at IS NULL",
              if_not_exists: true
  end
end
