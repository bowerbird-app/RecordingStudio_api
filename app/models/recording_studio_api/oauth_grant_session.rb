# frozen_string_literal: true

module RecordingStudioApi
  class OauthGrantSession < ApplicationRecord
    include RecordingStudio::Recordable

    self.table_name = "recording_studio_api_oauth_grant_sessions"

    belongs_to :oauth_client,
               class_name: "RecordingStudioApi::OauthClient",
               inverse_of: false
    belongs_to :access_recording,
               class_name: "RecordingStudio::Recording",
               inverse_of: false

    has_many :session_access_tokens,
             class_name: "RecordingStudioApi::OauthSessionAccessToken",
             dependent: :delete_all,
             inverse_of: :oauth_grant_session
    has_many :refresh_tokens,
             class_name: "RecordingStudioApi::OauthRefreshToken",
             dependent: :delete_all,
             inverse_of: :oauth_grant_session

    validates :oauth_client, presence: true
    validates :access_recording, presence: true
    validate :access_recording_must_reference_access
    validate :recording_topology_must_resolve_access, unless: :new_record?

    scope :active, -> { where(revoked_at: nil) }

    def recording
      @recording ||= RecordingStudio::Recording.unscoped.find_by(
        recordable_type: self.class.name,
        recordable_id: id,
        parent_recording_id: access_recording_id
      )
    end

    def api_client
      oauth_client
    end

    def effective_access_recording
      access_recording
    end

    def effective_access_recording_id
      access_recording_id
    end

    def active_for_authentication?
      revoked_at.nil? &&
        oauth_client&.active? &&
        access_recording.present? &&
        access_recording.trashed_at.nil? &&
        recording.present? &&
        recording.trashed_at.nil?
    end

    def revoke!(time: Time.current)
      update_columns(revoked_at: time, updated_at: time)
    end

    def revoke_family!(time: Time.current)
      revoke!(time: time)
      session_access_tokens.where(revoked_at: nil).update_all(revoked_at: time, updated_at: time)
      refresh_tokens.where(revoked_at: nil).update_all(revoked_at: time, updated_at: time)
    end

    def readonly?
      false
    end

    private

    def access_recording_must_reference_access
      return if access_recording.blank?
      return if access_recording.recordable_type == "RecordingStudio::Access"

      errors.add(:access_recording, "must point to a RecordingStudio::Access recording")
    end

    def recording_topology_must_resolve_access
      return if recording.present?

      errors.add(:base, "must be recorded as a child of a RecordingStudio::Access recording")
    end
  end
end