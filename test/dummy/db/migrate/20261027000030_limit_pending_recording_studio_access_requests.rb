# frozen_string_literal: true

# This migration comes from recording_studio_accessible (originally 20261016000030)
class LimitPendingRecordingStudioAccessRequests < ActiveRecord::Migration[8.1]
  def up
    add_column :recording_studio_access_requests, :target_recording_id, :uuid
    add_column :recording_studio_access_requests, :pending_key, :string
    backfill_targets
    keep_one_live_pending
    change_column_null :recording_studio_access_requests, :target_recording_id, false
    add_pending_index
  end

  def down
    remove_index :recording_studio_access_requests, name: INDEX_NAME
    remove_column :recording_studio_access_requests, :pending_key
    remove_column :recording_studio_access_requests, :target_recording_id
  end

  INDEX_NAME = "index_recording_studio_access_requests_one_pending"
  BACKFILL_SQL = <<~SQL.squish
    UPDATE recording_studio_access_requests AS requests
    SET target_recording_id = recordings.parent_recording_id
    FROM recording_studio_recordings AS recordings
    WHERE recordings.recordable_id = requests.id
      AND recordings.recordable_type = 'RecordingStudio::AccessRequest'
      AND recordings.parent_recording_id IS NOT NULL
  SQL
  DELETE_ORPHANS_SQL = <<~SQL.squish
    DELETE FROM recording_studio_access_requests WHERE target_recording_id IS NULL
  SQL
  CLOSE_EXTRAS_SQL = <<~SQL.squish
    UPDATE recording_studio_access_requests
    SET status = 'denied'
    WHERE id IN (
      SELECT id FROM (
        SELECT requests.id, row_number() OVER (
          PARTITION BY requests.target_recording_id, requests.actor_type, requests.actor_id
          ORDER BY requests.created_at DESC, requests.id DESC
        ) AS pending_rank
        FROM recording_studio_access_requests AS requests
        INNER JOIN recording_studio_recordings AS recordings
          ON recordings.recordable_id = requests.id
         AND recordings.recordable_type = 'RecordingStudio::AccessRequest'
        WHERE requests.status = 'pending'
      ) ranked
      WHERE pending_rank > 1
    )
  SQL
  STAMP_KEY_SQL = <<~SQL.squish
    UPDATE recording_studio_access_requests AS requests
    SET pending_key = requests.target_recording_id::text || ':' ||
      requests.actor_type || ':' || requests.actor_id::text
    FROM recording_studio_recordings AS recordings
    WHERE recordings.recordable_id = requests.id
      AND recordings.recordable_type = 'RecordingStudio::AccessRequest'
      AND requests.status = 'pending'
  SQL

  private

  def backfill_targets
    execute(BACKFILL_SQL)
    execute(DELETE_ORPHANS_SQL)
  end

  def keep_one_live_pending
    execute(CLOSE_EXTRAS_SQL)
    execute(STAMP_KEY_SQL)
  end

  def add_pending_index
    add_index :recording_studio_access_requests, :pending_key,
              unique: true, where: "pending_key IS NOT NULL", name: INDEX_NAME
  end
end
