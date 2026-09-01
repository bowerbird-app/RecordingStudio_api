# frozen_string_literal: true

class AddOauthAuthorizationToApiAccessTokens < ActiveRecord::Migration[8.1]
  def change
    change_column_null :recording_studio_api_api_access_tokens, :api_credential_id, true

    add_reference :recording_studio_api_api_access_tokens,
                  :oauth_authorization,
                  type: :uuid,
                  null: true,
                  foreign_key: { to_table: :recording_studio_api_oauth_authorizations }

    add_check_constraint :recording_studio_api_api_access_tokens,
                         "(api_credential_id IS NOT NULL AND oauth_authorization_id IS NULL) OR " \
                         "(api_credential_id IS NULL AND oauth_authorization_id IS NOT NULL)",
                         name: "api_access_tokens_credential_xor_authorization"
  end
end
