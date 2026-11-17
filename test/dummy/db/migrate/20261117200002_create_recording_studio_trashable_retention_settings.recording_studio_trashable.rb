# frozen_string_literal: true

# This migration comes from recording_studio_trashable (originally 20250101000002)
class CreateRecordingStudioTrashableRetentionSettings < ActiveRecord::Migration[8.1]
  def change
    return if table_exists?(:recording_studio_trashable_retention_settings)

    create_table :recording_studio_trashable_retention_settings, id: :uuid do |t|
      t.references :recording, null: false, type: :uuid, foreign_key: { to_table: :recording_studio_recordings },
                               index: { unique: true, name: "idx_rs_trashable_retention_on_recording" }
      t.integer :purge_after_days

      t.timestamps
    end
  end
end
