# frozen_string_literal: true

module RecordingStudioApi
  class ApiCredential < ApplicationRecord
    include RecordingStudio::Recordable

    self.table_name = "recording_studio_api_api_credentials"

    belongs_to :api_client,
               class_name: "RecordingStudioApi::ApiClient",
               inverse_of: :credentials
    # Legacy compatibility column. Recording topology is authoritative.
    belongs_to :access_recording,
               class_name: "RecordingStudio::Recording",
               inverse_of: false

    has_many :access_tokens,
         class_name: "RecordingStudioApi::ApiAccessToken",
         foreign_key: :api_credential_id,
         dependent: :destroy,
         inverse_of: :credential

    validates :token_public_id, presence: true, uniqueness: true
    validates :token_digest, presence: true, uniqueness: true
    validates :token_prefix, presence: true
    validate :access_recording_must_match_api_client
    validate :recording_topology_must_resolve_access, unless: :new_record?

    scope :active, lambda {
      where(revoked_at: nil).where(
        arel_table[:expires_at].eq(nil).or(arel_table[:expires_at].gt(Time.current))
      )
    }

    def recording
      @recording ||= RecordingStudio::Recording.unscoped.find_by(
        recordable_type: self.class.name,
        recordable_id: id,
        parent_recording_id: api_client&.recording&.id
      )
    end

    def effective_access_recording
      @effective_access_recording ||= begin
        parent_recording = recording&.parent_recording
        parent_access = parent_recording&.parent_recording
        parent_access if parent_access&.recordable_type == "RecordingStudio::Access"
      end
    end

    def effective_access_recording_id
      effective_access_recording&.id
    end

    def active_for_authentication?
      revoked_at.nil? &&
        (expires_at.nil? || expires_at.future?) &&
        effective_access_recording.present? &&
        effective_access_recording.trashed_at.nil? &&
        api_client.recording.present? &&
        api_client.recording.trashed_at.nil?
    end

    def revoke!(time: Time.current)
      update_columns(revoked_at: time, updated_at: time)
    end

    # Credentials remain mutable during transition while recordables become authoritative.
    def readonly?
      false
    end

    def oauth_client_id
      token_public_id
    end

    private

    def access_recording_must_match_api_client
      return if api_client.blank? || effective_access_recording.blank?
      return if api_client.access_recording_id == effective_access_recording_id

      errors.add(:access_recording, "must match the api client access recording")
    end

    def recording_topology_must_resolve_access
      return if effective_access_recording.present?

      errors.add(:base, "must be recorded as a child of an API client beneath a RecordingStudio::Access recording")
    end
  end
end
