# frozen_string_literal: true

require "recording_studio_trashable"

module RecordingStudioApi
  class ApiCredential < ApplicationRecord
    include RecordingStudio::Recordable
    include RecordingStudio::Capabilities::Trashable.to

    self.table_name = "recording_studio_api_api_credentials"

    recording_studio_recordable(
      label: "API Credential",
      plural_label: "API Credentials",
      root: false,
      allowed_parent_types: ["RecordingStudioApi::ApiClient"]
    )

    belongs_to :api_client,
               class_name: "RecordingStudioApi::ApiClient",
               inverse_of: :credentials

    has_many :access_tokens,
         class_name: "RecordingStudioApi::ApiAccessToken",
         foreign_key: :api_credential_id,
         dependent: :destroy,
         inverse_of: :credential

    validates :token_public_id, presence: true, uniqueness: true
    validates :token_digest, presence: true, uniqueness: true
    validates :token_prefix, presence: true
    validate :access_grant_actor_must_be_the_client, on: :create
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
        !expired? &&
        effective_access_recording.present? &&
        effective_access_recording.kept? &&
        api_client.recording.present? &&
        api_client.recording.kept? &&
        recording&.kept?
    end

    def expired?
      expires_at.present? && !expires_at.future?
    end

    def revoke!(time: Time.current)
      transaction do
        update_columns(revoked_at: time, updated_at: time)
        revoke_outstanding_access_tokens!(time: time)
      end
    end

    # Leaves the credential in an expired (not revoked) state for admin status, but
    # marks outstanding access tokens revoked so they cannot appear active.
    def revoke_outstanding_access_tokens!(time: Time.current)
      access_tokens.where(revoked_at: nil).update_all(revoked_at: time, updated_at: time)
    end

    def revoke_tokens_on_expiry!(time: Time.current)
      return unless expired?
      return if revoked_at.present?

      revoke_outstanding_access_tokens!(time: time)
    end

    def reload(*)
      remove_instance_variable(:@recording) if instance_variable_defined?(:@recording)
      remove_instance_variable(:@effective_access_recording) if instance_variable_defined?(:@effective_access_recording)
      super
    end

    # Credentials remain mutable during transition while recordables become authoritative.
    def readonly?
      false
    end

    def oauth_client_id
      token_public_id
    end

    private

    # ProvisionApiClient grants the Access with actor: api_client, so one grant
    # belongs to one client. The partial unique index on api_client_id then
    # allows one credential with revoked_at nil for that access.
    def access_grant_actor_must_be_the_client
      return if api_client.blank?

      access = api_client.recording&.parent_recording
      grant = access&.recordable
      return if access&.recordable_type == "RecordingStudio::Access" && grant&.actor == api_client

      errors.add(:base, "must sit under an access grant for this API client")
    end

    def recording_topology_must_resolve_access
      return if effective_access_recording.present?

      errors.add(:base, "must be recorded as a child of an API client beneath a RecordingStudio::Access recording")
    end
  end
end
