# frozen_string_literal: true

module RecordingStudioApi
  class OauthSessionAccessToken < ApplicationRecord
    include RecordingStudio::Recordable

    self.table_name = "recording_studio_api_oauth_session_access_tokens"

    belongs_to :oauth_grant_session,
               class_name: "RecordingStudioApi::OauthGrantSession",
               inverse_of: :session_access_tokens

    validates :token_digest, presence: true, uniqueness: true
    validates :token_prefix, presence: true
    validates :expires_at, presence: true
    validate :recording_topology_must_resolve_session, unless: :new_record?

    scope :active, lambda {
      where(revoked_at: nil).where(arel_table[:expires_at].gt(Time.current))
    }

    def recording
      @recording ||= RecordingStudio::Recording.unscoped.find_by(
        recordable_type: self.class.name,
        recordable_id: id,
        parent_recording_id: oauth_grant_session&.recording&.id
      )
    end

    def active_for_authentication?
      revoked_at.nil? &&
        expires_at.present? &&
        expires_at.future? &&
        oauth_grant_session&.active_for_authentication? &&
        recording.present? &&
        recording.trashed_at.nil?
    end

    def revoke!(time: Time.current)
      update_columns(revoked_at: time, updated_at: time)
    end

    def readonly?
      false
    end

    private

    def recording_topology_must_resolve_session
      return if recording.present?

      errors.add(:base, "must be recorded as a child of an OAuth grant session recording")
    end
  end
end