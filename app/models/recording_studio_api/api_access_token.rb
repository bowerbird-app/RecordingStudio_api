# frozen_string_literal: true

module RecordingStudioApi
  class ApiAccessToken < ApplicationRecord
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

    def active_for_authentication?
      revoked_at.nil? && expires_at.present? && expires_at.future?
    end

    def revoke!(time: Time.current)
      update!(revoked_at: time)
    end
  end
end