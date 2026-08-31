# frozen_string_literal: true

class DropRecordingStudioDeviceSessions < ActiveRecord::Migration[8.1]
  def up
    drop_table :recording_studio_device_sessions, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "device sessions were removed from Recording Studio 4.x"
  end
end
