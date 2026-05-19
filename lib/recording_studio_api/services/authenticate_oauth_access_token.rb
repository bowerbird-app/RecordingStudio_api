# frozen_string_literal: true

module RecordingStudioApi
  module Services
    class AuthenticateOauthAccessToken < TokenAuthenticationBase

      private

      def missing_token_error_message
        "Bearer access token is required"
      end

      def invalid_token_format_error_message
        "Bearer access token format is invalid"
      end

      def invalid_token_error_message
        "Bearer access token is invalid"
      end

      def inactive_token_error_message
        "Bearer access token is inactive"
      end

      def invalid_scope_error_message
        "Bearer access token scope is invalid"
      end

      def valid_token_format?(token)
        OauthAccessToken.valid_format?(token)
      end

      def resolve_authenticated_entities(token)
        provided_digest = OauthAccessToken.digest(token)
        access_token = ApiAccessToken.includes(credential: :api_client).find_by(token_digest: provided_digest)
        return [nil, nil] if access_token.nil?

        credential = access_token.credential
        return [nil, nil] if credential.nil?

        [credential, access_token]
      end

      def token_record_active?(token_record)
        token_record&.active_for_authentication? || false
      end

      def update_last_used!(credential, token_record)
        token_record&.update_column(:last_used_at, Time.current)
        credential.update_column(:last_used_at, Time.current)
      end

    end
  end
end