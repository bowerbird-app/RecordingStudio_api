# frozen_string_literal: true

module RecordingStudioApi
  class OauthAuthorizationCode < ApplicationRecord
    include RecordingStudio::Recordable

    self.table_name = "recording_studio_api_oauth_authorization_codes"

    recording_studio_recordable(
      label: "OAuth Authorization Code",
      plural_label: "OAuth Authorization Codes",
      root: false,
      allowed_parent_types: ["RecordingStudio::Access"]
    )

    belongs_to :oauth_client,
               class_name: "RecordingStudioApi::OauthClient",
               inverse_of: :authorization_codes
    belongs_to :access_recording,
               class_name: "RecordingStudio::Recording",
               inverse_of: false

    validates :code_digest, presence: true, uniqueness: true
    validates :code_prefix, presence: true
    validates :code_challenge, presence: true
    validates :code_challenge_method, presence: true
    validates :redirect_uri, presence: true
    validates :expires_at, presence: true
    validate :access_recording_must_reference_access
    validate :recording_topology_must_resolve_access, unless: :new_record?

    scope :active, lambda {
      where(consumed_at: nil).where(arel_table[:expires_at].gt(Time.current))
    }

    def active?
      consumed_at.nil? && expires_at.present? && expires_at.future?
    end

    def consume!(time: Time.current)
      update_columns(consumed_at: time, updated_at: time)
    end

    def recording
      @recording ||= RecordingStudio::Recording.unscoped.find_by(
        recordable_type: self.class.name,
        recordable_id: id,
        parent_recording_id: access_recording_id
      )
    end

    def active_for_authentication?
      consumed_at.nil? &&
        expires_at.present? &&
        expires_at.future? &&
        access_recording.present? &&
        access_recording.trashed_at.nil? &&
        recording.present? &&
        recording.trashed_at.nil? &&
        oauth_client.active?
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