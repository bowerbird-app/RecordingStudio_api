# frozen_string_literal: true

module RecordingStudioApi
  class ApiCredential < ApplicationRecord
    self.table_name = "recording_studio_api_api_credentials"

    belongs_to :api_client,
               class_name: "RecordingStudioApi::ApiClient",
               inverse_of: :credentials
    belongs_to :access_recording,
               class_name: "RecordingStudio::Recording",
               inverse_of: false

    validates :token_public_id, presence: true, uniqueness: true
    validates :token_digest, presence: true, uniqueness: true
    validates :token_prefix, presence: true
    validate :access_recording_must_match_api_client

    scope :active, lambda {
      where(revoked_at: nil).where(
        arel_table[:expires_at].eq(nil).or(arel_table[:expires_at].gt(Time.current))
      )
    }

    def active_for_authentication?
      revoked_at.nil? &&
        (expires_at.nil? || expires_at.future?) &&
        access_recording.present? &&
        access_recording.trashed_at.nil? &&
        api_client.recording.present? &&
        api_client.recording.trashed_at.nil?
    end

    def revoke!(time: Time.current)
      update!(revoked_at: time)
    end

    private

    def access_recording_must_match_api_client
      return if api_client.blank? || access_recording.blank?
      return if api_client.access_recording_id == access_recording_id

      errors.add(:access_recording, "must match the api client access recording")
    end
  end
end
