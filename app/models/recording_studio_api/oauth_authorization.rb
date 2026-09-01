# frozen_string_literal: true

module RecordingStudioApi
  class OauthAuthorization < ApplicationRecord
    self.table_name = "recording_studio_api_oauth_authorizations"

    ROLES = %w[view edit admin].freeze

    belongs_to :oauth_client, class_name: "RecordingStudioApi::OauthClient", inverse_of: :authorizations
    belongs_to :manager_actor, polymorphic: true
    belongs_to :manager_access_recording,
               class_name: "RecordingStudio::Recording",
               inverse_of: false
    belongs_to :access_recording,
               class_name: "RecordingStudio::Recording",
               inverse_of: false,
               optional: true

    has_many :authorization_codes,
             class_name: "RecordingStudioApi::OauthAuthorizationCode",
             dependent: :destroy,
             inverse_of: :oauth_authorization
    has_many :refresh_tokens,
             class_name: "RecordingStudioApi::OauthRefreshToken",
             dependent: :destroy,
             inverse_of: :oauth_authorization
    has_many :access_tokens,
             class_name: "RecordingStudioApi::ApiAccessToken",
             dependent: :nullify,
             inverse_of: :oauth_authorization

    validates :role, presence: true, inclusion: { in: ROLES }

    scope :active, -> { where(revoked_at: nil) }

    def name
      oauth_client&.name.presence || "Connected app"
    end

    def revoked?
      revoked_at.present?
    end

    def active?
      !revoked? && granted_access_recording_active? && accessible_authorized?
    end

    def granted_access_recording_active?
      access_recording.present? && access_recording.trashed_at.nil?
    end

    def workspace_recording
      access_recording&.parent_recording || access_recording&.root_recording ||
        manager_access_recording&.parent_recording || manager_access_recording&.root_recording
    end

    def accessible_authorized?
      workspace = workspace_recording
      return false if workspace.blank? || workspace.trashed_at.present?

      RecordingStudioAccessible.authorized?(
        actor: self,
        recording: workspace,
        role: role
      )
    end

    def self.role_rank(role)
      RecordingStudioApi::Configuration::ACCESS_ROLE_RANKS[role.to_s.to_sym]
    end

    def self.role_at_or_below?(requested, current)
      requested_rank = role_rank(requested)
      current_rank = role_rank(current)
      requested_rank.present? && current_rank.present? && requested_rank <= current_rank
    end

    def self.for_client_manager_and_access(oauth_client:, manager_actor:, access_recording:)
      find_by(
        oauth_client: oauth_client,
        manager_actor: manager_actor,
        manager_access_recording: access_recording
      )
    end
  end
end
