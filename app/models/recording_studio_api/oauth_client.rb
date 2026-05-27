# frozen_string_literal: true

module RecordingStudioApi
  class OauthClient < ApplicationRecord
    self.table_name = "recording_studio_api_oauth_clients"

    has_many :authorization_codes,
             class_name: "RecordingStudioApi::OauthAuthorizationCode",
             dependent: :delete_all,
             inverse_of: :oauth_client

    validates :name, presence: true
    validates :client_identifier, presence: true, uniqueness: true
    validates :redirect_uri, presence: true
  end
end