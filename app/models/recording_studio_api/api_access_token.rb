# frozen_string_literal: true

module RecordingStudioApi
  class ApiAccessToken < ApplicationRecord
    include RecordingStudio::Recordable

    self.table_name = "recording_studio_api_api_access_tokens"

    recording_studio_recordable(
      label: "API Access Token",
      plural_label: "API Access Tokens",
      root: false,
      allowed_parent_types: ["RecordingStudioApi::ApiCredential"]
    )

    belongs_to :credential,
               class_name: "RecordingStudioApi::ApiCredential",
               foreign_key: :api_credential_id,
               inverse_of: :access_tokens,
               optional: true
    belongs_to :oauth_authorization,
               class_name: "RecordingStudioApi::OauthAuthorization",
               inverse_of: :access_tokens,
               optional: true

    validates :token_digest, presence: true, uniqueness: true
    validates :token_prefix, presence: true
    validates :expires_at, presence: true
    validate :credential_xor_oauth_authorization
    validate :recording_topology_must_resolve_credential, unless: :new_record?

    scope :active, lambda {
      where(revoked_at: nil).where(arel_table[:expires_at].gt(Time.current))
    }

    def recording
      return if delegated?

      @recording ||= RecordingStudio::Recording.unscoped.find_by(
        recordable_type: self.class.name,
        recordable_id: id,
        parent_recording_id: credential_recording&.id
      )
    end

    def delegated?
      oauth_authorization_id.present?
    end

    def effective_access_recording
      if delegated?
        oauth_authorization&.access_recording
      else
        credential&.effective_access_recording
      end
    end

    def active_for_authentication?
      return delegated_active_for_authentication? if delegated?

      revoked_at.nil? &&
        expires_at.present? &&
        expires_at.future? &&
        credential_recording.present? &&
        credential_recording.trashed_at.nil? &&
        recording.present? &&
        recording.trashed_at.nil?
    end

    def revoke!(time: Time.current)
      update_columns(revoked_at: time, updated_at: time) if revoked_at.nil?
    end

    def readonly?
      false
    end

    private

    def delegated_active_for_authentication?
      revoked_at.nil? &&
        expires_at.present? &&
        expires_at.future? &&
        oauth_authorization.present? &&
        oauth_authorization.active?
    end

    def credential_recording
      @credential_recording ||= credential&.recording
    end

    def credential_xor_oauth_authorization
      credential_present = api_credential_id.present?
      authorization_present = oauth_authorization_id.present?
      return if credential_present ^ authorization_present

      errors.add(:base, "must belong to either an API credential or an OAuth authorization")
    end

    def recording_topology_must_resolve_credential
      return if delegated?
      return if recording.present?

      errors.add(:base, "must be recorded as a child of an API credential recording")
    end
  end
end
