# frozen_string_literal: true

class CreateRecordingStudioApiOauthClients < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_api_oauth_clients, id: :uuid do |t|
      t.string :name, null: false
      t.string :client_id, null: false
      t.string :client_secret_digest
      t.jsonb :redirect_uris, null: false, default: []
      t.boolean :confidential, null: false, default: true
      t.string :api_key, null: false, default: "public"
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :recording_studio_api_oauth_clients, :client_id, unique: true
    add_index :recording_studio_api_oauth_clients, :api_key
  end
end
