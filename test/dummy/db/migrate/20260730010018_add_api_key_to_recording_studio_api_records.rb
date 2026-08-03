# frozen_string_literal: true

class AddApiKeyToRecordingStudioApiRecords < ActiveRecord::Migration[8.1]
  def change
    add_column :recording_studio_api_api_clients, :api_key, :string, null: false, default: "public"
    add_index :recording_studio_api_api_clients, :api_key
  end
end