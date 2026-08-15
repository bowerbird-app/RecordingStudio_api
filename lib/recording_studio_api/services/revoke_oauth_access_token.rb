# frozen_string_literal: true

module RecordingStudioApi
  module Services
    # RFC 7009-style OAuth token revocation for issued access tokens.
    # Unknown or already-revoked tokens still succeed once the client authenticates.
    class RevokeOauthAccessToken < BaseService
      def initialize(token:, client_id:, client_secret:, token_type_hint: nil, api: :public)
        @token = token.to_s
        @client_id = client_id.to_s
        @client_secret = client_secret.to_s
        @token_type_hint = token_type_hint.to_s.presence
        @api_key = RecordingStudioApi.configuration.fetch_api(api).name
      end

      private

      attr_reader :token, :client_id, :client_secret, :token_type_hint, :api_key

      def perform
        return oauth_failure("invalid_request", "client_id is required") if client_id.blank?
        return oauth_failure("invalid_request", "client_secret is required") if client_secret.blank?
        return oauth_failure("invalid_request", "token is required") if token.blank?

        credential = ApiCredential.joins(:api_client)
                                  .merge(ApiClient.where(api_key: api_key))
                                  .find_by(token_public_id: client_id)
        return oauth_failure("invalid_client", "client authentication failed") unless authenticate_client?(credential)

        revoke_matching_access_token!(credential) if OauthAccessToken.valid_format?(token) || token_type_hint == "access_token"

        success({})
      rescue ActiveRecord::ActiveRecordError
        failure(OauthErrorMapper.server_error_payload)
      end

      def oauth_failure(code, description)
        failure({ error: code, error_description: description })
      end

      def authenticate_client?(credential)
        expected_digest = credential&.token_digest.presence || Token.digest(IssueOauthAccessToken::DUMMY_CLIENT_SECRET)
        secret_matches = Token.digest_matches?(expected_digest, client_secret)
        TokenDigest.rehash_if_legacy!(credential, client_secret) if secret_matches && credential.present?

        credential.present? && credential.active_for_authentication? && secret_matches
      end

      def revoke_matching_access_token!(credential)
        access_token = OauthAccessToken.find_by_token(credential.access_tokens, token)
        return if access_token.nil?
        return if access_token.revoked_at.present?

        access_token.revoke!
      end

      def service_args
        {
          api_key: api_key,
          token_present: token.present?,
          client_id_present: client_id.present?,
          client_secret_present: client_secret.present?,
          token_type_hint: token_type_hint
        }
      end
    end
  end
end
