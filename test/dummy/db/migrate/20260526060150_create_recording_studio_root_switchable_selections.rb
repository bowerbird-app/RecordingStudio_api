# frozen_string_literal: true

class CreateRecordingStudioRootSwitchableSelections < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_root_switchable_selections, id: :uuid do |t|
      t.string :actor_type
      t.string :actor_id
      t.string :device_key, null: false
      t.uuid :root_recording_id, null: false
      t.string :scope_key, null: false
      t.datetime :last_used_at, null: false

      t.timestamps
    end

    add_index :recording_studio_root_switchable_selections,
              %i[actor_type actor_id device_key scope_key],
              unique: true,
              where: "actor_id IS NOT NULL",
              name: "idx_rs_root_switchable_actor_device_scope"
    add_index :recording_studio_root_switchable_selections,
              %i[device_key scope_key],
              unique: true,
              where: "actor_id IS NULL",
              name: "idx_rs_root_switchable_anonymous_device_scope"
    add_index :recording_studio_root_switchable_selections,
              :root_recording_id,
              name: "idx_rs_root_switchable_root_recording"

    add_foreign_key :recording_studio_root_switchable_selections,
                    :recording_studio_recordings,
                    column: :root_recording_id
  end
end
