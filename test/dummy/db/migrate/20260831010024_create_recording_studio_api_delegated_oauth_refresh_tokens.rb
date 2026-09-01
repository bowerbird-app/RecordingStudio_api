# frozen_string_literal: true

class CreateRecordingStudioApiDelegatedOauthRefreshTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_api_oauth_refresh_tokens, id: :uuid do |t|
      t.references :oauth_authorization,
                   null: false,
                   type: :uuid,
                   foreign_key: { to_table: :recording_studio_api_oauth_authorizations }
      t.string :token_digest, null: false
      t.string :token_prefix, null: false
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.uuid :replaced_by_id

      t.timestamps
    end

    add_index :recording_studio_api_oauth_refresh_tokens, :token_digest, unique: true
    add_index :recording_studio_api_oauth_refresh_tokens, :expires_at
    add_index :recording_studio_api_oauth_refresh_tokens, :replaced_by_id
  end
end
