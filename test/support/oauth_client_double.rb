# frozen_string_literal: true

module RecordingStudioOauth
  # Test stand-in for the OAuth gem's client. Same row as an API client, different class name,
  # so event actor_type can be the OAuth client without a migration.
  class OauthClient < ActiveRecord::Base
    self.table_name = "recording_studio_api_api_clients"
  end
end
