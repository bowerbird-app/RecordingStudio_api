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
      !revoked? && granted_access_recording_active?
    end

    def granted_access_recording_active?
      access_recording.present? && access_recording.trashed_at.nil?
    end

    def workspace_recording
      access_recording&.parent_recording || access_recording&.root_recording ||
        manager_access_recording&.parent_recording || manager_access_recording&.root_recording
    end

    def manager_role_rank
      role_rank(RecordingStudioAccessible.role_for(actor: manager_actor, recording: workspace_recording))
    end

    def granted_role_rank
      role_rank(role)
    end

    def manager_qualifies?
      return false if revoked?
      return false if manager_actor.blank?
      return false unless granted_access_recording_active?
      return false if workspace_recording.blank? || workspace_recording.trashed_at.present?

      manager_rank = manager_role_rank
      granted_rank = granted_role_rank
      manager_rank.present? && granted_rank.present? && manager_rank >= granted_rank
    end

    private

    def role_rank(role_name)
      return if role_name.blank?

      RecordingStudioApi::Configuration::ACCESS_ROLE_RANKS[role_name.to_s.to_sym]
    end
  end
end
