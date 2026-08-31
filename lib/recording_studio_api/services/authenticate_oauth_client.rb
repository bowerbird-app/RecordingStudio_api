# frozen_string_literal: true

module RecordingStudioApi
  module Services
    class AuthenticateOauthClient < BaseService
      DUMMY_CLIENT_SECRET = IssueOauthAccessToken::DUMMY_CLIENT_SECRET

      def initialize(client_id:, client_secret:, api: :public, allow_public: false)
        @client_id = client_id.to_s
        @client_secret = client_secret.to_s
        @api_key = RecordingStudioApi.configuration.fetch_api(api).name
        @allow_public = allow_public
      end

      private

      attr_reader :client_id, :client_secret, :api_key, :allow_public

      def perform
        resolved = ResolveOauthClient.call(client_id: client_id, api: api_key)
        client = resolved.success? ? resolved.value : nil

        if client&.public?
          dummy_compare_secret
          return oauth_failure("invalid_client", "client authentication failed") unless allow_public

          return success(client)
        end

        expected_digest = client&.client_secret_digest.presence || dummy_client_secret_digest
        secret_matches = Token.digest_matches?(expected_digest, client_secret)
        TokenDigest.rehash_if_legacy!(client, client_secret) if secret_matches && client.present? && client.respond_to?(:client_secret_digest)

        return oauth_failure("invalid_client", "client authentication failed") if client.blank? || !secret_matches
        return oauth_failure("invalid_client", "client authentication failed") unless client.active?

        success(client)
      end

      def dummy_compare_secret
        Token.digest_matches?(dummy_client_secret_digest, client_secret.presence || DUMMY_CLIENT_SECRET)
      end

      def dummy_client_secret_digest
        Token.digest(DUMMY_CLIENT_SECRET)
      end

      def oauth_failure(code, description)
        failure({ error: code, error_description: description })
      end

      def service_args
        {
          api_key: api_key,
          client_id_present: client_id.present?,
          client_secret_present: client_secret.present?,
          allow_public: allow_public
        }
      end
    end
  end
end
