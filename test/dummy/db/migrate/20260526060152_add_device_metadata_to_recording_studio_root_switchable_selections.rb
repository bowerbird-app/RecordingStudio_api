# frozen_string_literal: true

class AddDeviceMetadataToRecordingStudioRootSwitchableSelections < ActiveRecord::Migration[8.1]
  def change
    change_table :recording_studio_root_switchable_selections, bulk: true do |t|
      t.string :device_label
      t.string :device_platform
      t.string :device_browser
      t.string :device_type
      t.text :user_agent
    end
  end
end
