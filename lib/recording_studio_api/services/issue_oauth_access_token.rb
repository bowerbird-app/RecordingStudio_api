# frozen_string_literal: true

module RecordingStudioApi
  module Services
    class IssueOauthAccessToken < BaseService
      SUPPORTED_GRANT_TYPE = "client_credentials"

      def initialize(grant_type:, client_id:, client_secret:)
        @grant_type = grant_type
        @client_id = client_id
        @client_secret = client_secret
      end

      private

      attr_reader :grant_type, :client_id, :client_secret

      def perform
        return oauth_failure("unsupported_grant_type", "grant_type must be client_credentials") unless grant_type == SUPPORTED_GRANT_TYPE
        return oauth_failure("invalid_request", "client_id is required") if client_id.blank?
        return oauth_failure("invalid_request", "client_secret is required") if client_secret.blank?

        credential = ApiCredential.find_by(token_public_id: client_id)
        return oauth_failure("invalid_client", "client authentication failed") if credential.nil?
        return oauth_failure("invalid_client", "client authentication failed") unless credential.active_for_authentication?

        provided_digest = Token.digest(client_secret)
        return oauth_failure("invalid_client", "client authentication failed") unless secure_compare(credential.token_digest, provided_digest)

        token_data = OauthAccessToken.generate
        expires_at = resolved_expiry

        access_token = ApiAccessToken.create!(
          credential: credential,
          token_digest: token_data.fetch(:digest),
          token_prefix: token_data.fetch(:prefix),
          expires_at: expires_at
        )

        success(
          {
            access_token: token_data.fetch(:token),
            token_type: "Bearer",
            expires_in: (expires_at - Time.current).to_i,
            created_at: access_token.created_at.to_i,
            api_client_id: credential.api_client_id
          }
        )
      rescue ActiveRecord::ActiveRecordError => e
        failure(e)
      end

      def oauth_failure(code, description)
        failure({ error: code, error_description: description })
      end

      def secure_compare(left, right)
        return false if left.blank? || right.blank?
        return false unless left.bytesize == right.bytesize

        ActiveSupport::SecurityUtils.secure_compare(left, right)
      end

      def resolved_expiry
        ttl = RecordingStudioApi.configuration.token_ttl
        ttl.present? ? Time.current + ttl : 30.minutes.from_now
      end

      def service_args
        {
          grant_type: grant_type,
          client_id_present: client_id.present?,
          client_secret_present: client_secret.present?
        }
      end
    end
  end
end