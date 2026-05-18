# frozen_string_literal: true

module RecordingStudioApi
  module Services
    class AuthenticateBearerToken < BaseService
      def initialize(authorization_header:)
        @authorization_header = authorization_header
      end

      private

      attr_reader :authorization_header

      def perform
        token = parse_bearer_token
        return failure(AuthenticationError.new("Bearer token is required")) if token.blank?

        parsed = Token.parse(token)
        return failure(AuthenticationError.new("Bearer token format is invalid")) if parsed.nil?

        credential = ApiCredential.find_by(token_public_id: parsed.fetch(:public_id))
        return failure(AuthenticationError.new("Bearer token is invalid")) if credential.nil?
        return failure(AuthenticationError.new("Bearer token is inactive")) unless credential.active_for_authentication?

        provided_digest = Token.digest(parsed.fetch(:token))
        return failure(AuthenticationError.new("Bearer token is invalid")) unless secure_compare(credential.token_digest, provided_digest)

        credential.update_column(:last_used_at, Time.current)

        success(
          AuthenticatedClient.new(
            api_client: credential.api_client,
            credential: credential,
            access_recording: credential.access_recording,
            root_recording: credential.access_recording.root_recording
          )
        )
      end

      def parse_bearer_token
        return if authorization_header.blank?

        scheme, token = authorization_header.to_s.split(" ", 2)
        return unless scheme.to_s.casecmp("Bearer").zero?

        token
      end

      def secure_compare(left, right)
        return false if left.blank? || right.blank?
        return false unless left.bytesize == right.bytesize

        ActiveSupport::SecurityUtils.secure_compare(left, right)
      end

      def service_args
        { authorization_header_present: authorization_header.present? }
      end
    end
  end
end
