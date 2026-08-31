# frozen_string_literal: true

class CreateRecordingStudioApiOauthAuthorizations < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_api_oauth_authorizations, id: :uuid do |t|
      t.references :oauth_client,
                   null: false,
                   type: :uuid,
                   foreign_key: { to_table: :recording_studio_api_oauth_clients }
      t.string :manager_actor_type, null: false
      t.uuid :manager_actor_id, null: false
      t.uuid :manager_access_recording_id, null: false
      t.uuid :access_recording_id
      t.string :role, null: false
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :recording_studio_api_oauth_authorizations,
              %i[manager_actor_type manager_actor_id],
              name: "index_rs_api_oauth_authorizations_on_manager_actor"
    add_index :recording_studio_api_oauth_authorizations, :manager_access_recording_id
    add_index :recording_studio_api_oauth_authorizations, :access_recording_id
    add_index :recording_studio_api_oauth_authorizations, :revoked_at
  end
end
