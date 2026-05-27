# frozen_string_literal: true

module RecordingStudioApi
  module Services
    class RevokeOauthToken < BaseService
      def initialize(client_id:, token:, token_type_hint: nil)
        @client_id = client_id
        @token = token
        @token_type_hint = token_type_hint
      end

      private

      attr_reader :client_id, :token, :token_type_hint

      def perform
        return oauth_failure("invalid_request", "token is required") if token.blank?
        return oauth_failure("invalid_request", "client_id is required") if client_id.blank?

        oauth_client = OauthClient.find_by(client_identifier: client_id)
        return oauth_failure("invalid_client", "client authentication failed") if oauth_client.nil?

        session = resolve_session_for_token
        return success(nil) if session.nil?
        return success(nil) unless session.oauth_client_id == oauth_client.id

        session.revoke_family!
        success(nil)
      rescue ActiveRecord::ActiveRecordError => e
        failure(e)
      end

      def resolve_session_for_token
        return session_for_refresh_token if token_type_hint == "refresh_token"
        return session_for_access_token if token_type_hint == "access_token"

        session_for_refresh_token || session_for_access_token
      end

      def session_for_refresh_token
        return unless OauthRefreshTokenValue.valid_format?(token)

        OauthRefreshToken.find_by(token_digest: OauthRefreshTokenValue.digest(token))&.oauth_grant_session
      end

      def session_for_access_token
        return unless OauthAccessToken.valid_format?(token)

        OauthSessionAccessToken.find_by(token_digest: OauthAccessToken.digest(token))&.oauth_grant_session
      end

      def oauth_failure(code, description)
        failure({ error: code, error_description: description })
      end

      def service_args
        {
          client_id_present: client_id.present?,
          token_present: token.present?,
          token_type_hint: token_type_hint
        }
      end
    end
  end
end
