# frozen_string_literal: true

module RecordingStudioApi
  class ApiAccessToken < ApplicationRecord
    include RecordingStudio::Recordable

    self.table_name = "recording_studio_api_api_access_tokens"

    belongs_to :credential,
               class_name: "RecordingStudioApi::ApiCredential",
               foreign_key: :api_credential_id,
               inverse_of: :access_tokens

    validates :token_digest, presence: true, uniqueness: true
    validates :token_prefix, presence: true
    validates :expires_at, presence: true

    scope :active, lambda {
      where(revoked_at: nil).where(arel_table[:expires_at].gt(Time.current))
    }

    validate :recording_topology_must_resolve_credential, unless: :new_record?

    def recording
      @recording ||= RecordingStudio::Recording.unscoped.find_by(
        recordable_type: self.class.name,
        recordable_id: id,
        parent_recording_id: credential_recording&.id
      )
    end

    def active_for_authentication?
      revoked_at.nil? &&
        expires_at.present? &&
        expires_at.future? &&
        credential_recording.present? &&
        credential_recording.trashed_at.nil? &&
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

    def credential_recording
      @credential_recording ||= credential&.recording
    end

    def recording_topology_must_resolve_credential
      return if recording.present?

      errors.add(:base, "must be recorded as a child of an API credential recording")
    end
  end
end