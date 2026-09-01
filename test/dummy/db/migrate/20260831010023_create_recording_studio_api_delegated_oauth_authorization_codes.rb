# frozen_string_literal: true

class CreateRecordingStudioApiDelegatedOauthAuthorizationCodes < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_api_oauth_authorization_codes, id: :uuid do |t|
      t.references :oauth_authorization,
                   null: false,
                   type: :uuid,
                   foreign_key: { to_table: :recording_studio_api_oauth_authorizations }
      t.string :code_digest, null: false
      t.string :redirect_uri, null: false
      t.string :code_challenge
      t.string :code_challenge_method
      t.datetime :expires_at, null: false
      t.datetime :used_at

      t.timestamps
    end

    add_index :recording_studio_api_oauth_authorization_codes, :code_digest, unique: true
    add_index :recording_studio_api_oauth_authorization_codes, :expires_at
  end
end
