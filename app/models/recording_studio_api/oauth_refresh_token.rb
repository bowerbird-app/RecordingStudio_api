# frozen_string_literal: true

module RecordingStudioApi
  class OauthRefreshToken < ApplicationRecord
    self.table_name = "recording_studio_api_oauth_refresh_tokens"

    belongs_to :oauth_authorization,
               class_name: "RecordingStudioApi::OauthAuthorization",
               inverse_of: :refresh_tokens
    belongs_to :replaced_by,
               class_name: "RecordingStudioApi::OauthRefreshToken",
               optional: true,
               inverse_of: false

    validates :token_digest, presence: true, uniqueness: true
    validates :token_prefix, presence: true
    validates :expires_at, presence: true

    scope :active, lambda {
      where(revoked_at: nil).where(arel_table[:expires_at].gt(Time.current))
    }

    def revoked?
      revoked_at.present?
    end

    def expired?
      expires_at.blank? || !expires_at.future?
    end

    def active?
      !revoked? && !expired?
    end

    def revoke!(time: Time.current)
      update_columns(revoked_at: time, updated_at: time) if revoked_at.nil?
    end
  end
end
