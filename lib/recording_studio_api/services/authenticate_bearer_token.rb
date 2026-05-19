# frozen_string_literal: true

module RecordingStudioApi
  module Services
    class AuthenticateBearerToken < TokenAuthenticationBase

      private

      def missing_token_error_message
        "Bearer token is required"
      end

      def invalid_token_format_error_message
        "Bearer token format is invalid"
      end

      def invalid_token_error_message
        "Bearer token is invalid"
      end

      def inactive_token_error_message
        "Bearer token is inactive"
      end

      def invalid_scope_error_message
        "Bearer token scope is invalid"
      end

      def valid_token_format?(token)
        Token.parse(token).present?
      end

      def resolve_authenticated_entities(token)
        parsed = Token.parse(token)
        return [nil, nil] if parsed.nil?

        credential = ApiCredential.find_by(token_public_id: parsed.fetch(:public_id))
        return [nil, nil] if credential.nil?

        provided_digest = Token.digest(parsed.fetch(:token))
        return [nil, nil] unless secure_compare(credential.token_digest, provided_digest)

        [credential, nil]
      end
    end
  end
end
