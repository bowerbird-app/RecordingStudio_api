# frozen_string_literal: true

module RecordingStudioApi
  class OauthClient < ApplicationRecord
    self.table_name = "recording_studio_api_oauth_clients"

    has_many :authorizations,
             class_name: "RecordingStudioApi::OauthAuthorization",
             dependent: :destroy,
             inverse_of: :oauth_client

    validates :name, presence: true
    validates :client_id, presence: true, uniqueness: true
    validates :api_key, presence: true, inclusion: { in: ->(_) { RecordingStudioApi.configuration.api_names } }
    validates :redirect_uris, presence: true
    validate :redirect_uris_must_be_absolute
    validate :confidential_clients_require_secret_digest
    validate :api_key_must_not_change, on: :update

    scope :active, -> { where(revoked_at: nil) }

    def public?
      !confidential?
    end

    def revoked?
      revoked_at.present?
    end

    def active?
      !revoked?
    end

    def redirect_uri_allowed?(uri)
      normalized = uri.to_s
      Array(redirect_uris).any? { |allowed| allowed.to_s == normalized }
    end

    def authenticate_secret?(secret)
      return false if public?
      return false if client_secret_digest.blank? || secret.blank?

      Token.digest_matches?(client_secret_digest, secret)
    end

    private

    def redirect_uris_must_be_absolute
      Array(redirect_uris).each do |uri|
        parsed = URI.parse(uri.to_s)
        next if parsed.is_a?(URI::HTTP) && parsed.host.present? && parsed.fragment.nil?

        errors.add(:redirect_uris, "must be absolute HTTP(S) URIs without fragments")
        break
      rescue URI::InvalidURIError
        errors.add(:redirect_uris, "must be valid URIs")
        break
      end
    end

    def confidential_clients_require_secret_digest
      return unless confidential?
      return if client_secret_digest.present?

      errors.add(:client_secret_digest, "is required for confidential clients")
    end

    def api_key_must_not_change
      errors.add(:api_key, "cannot be changed") if will_save_change_to_api_key?
    end
  end
end
