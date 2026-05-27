# frozen_string_literal: true

require "base64"
require "digest"

module RecordingStudioApi
  module Services
    class ExchangeOauthAuthorizationCode < BaseService
      ACCESS_TOKEN_TTL_SECONDS = 900
      REFRESH_TOKEN_TTL_SECONDS = 2_592_000
      CODE_CHALLENGE_METHOD = "S256"

      def initialize(grant_type:, client_id:, code:, redirect_uri:, code_verifier:)
        @grant_type = grant_type
        @client_id = client_id
        @code = code
        @redirect_uri = redirect_uri
        @code_verifier = code_verifier
      end

      private

      attr_reader :grant_type, :client_id, :code, :redirect_uri, :code_verifier

      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
      def perform
        return oauth_failure("unsupported_grant_type", "grant_type must be authorization_code") unless grant_type == "authorization_code"
        return oauth_failure("invalid_request", "client_id is required") if client_id.blank?
        return oauth_failure("invalid_request", "code is required") if code.blank?
        return oauth_failure("invalid_request", "redirect_uri is required") if redirect_uri.blank?
        return oauth_failure("invalid_request", "code_verifier is required") if code_verifier.blank?

        oauth_client = OauthClient.find_by(client_identifier: client_id, active: true, public_client: true)
        return oauth_failure("invalid_client", "client authentication failed") if oauth_client.nil?

        payload = nil
        now = Time.current
        code_digest = Digest::SHA256.hexdigest(code)
        expected_challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false)

        # rubocop:disable Metrics/BlockLength
        OauthGrantSession.transaction do
          authorization_code = OauthAuthorizationCode.lock.find_by(code_digest: code_digest)
          return oauth_failure("invalid_grant", "authorization code is invalid") if authorization_code.nil?
          return oauth_failure("invalid_grant", "authorization code is invalid") unless authorization_code.active_for_authentication?
          return oauth_failure("invalid_grant", "authorization code is invalid") unless authorization_code.oauth_client_id == oauth_client.id
          return oauth_failure("invalid_grant", "redirect_uri is invalid") unless authorization_code.redirect_uri == redirect_uri
          return oauth_failure("invalid_grant", "code_challenge_method is invalid") unless authorization_code.code_challenge_method == CODE_CHALLENGE_METHOD
          return oauth_failure("invalid_grant", "code_verifier is invalid") unless secure_compare(authorization_code.code_challenge, expected_challenge)

          access_recording = authorization_code.access_recording
          return oauth_failure("invalid_scope", "access recording is invalid") if access_recording.nil? || access_recording.trashed_at.present?

          consumed_rows = OauthAuthorizationCode.where(id: authorization_code.id, consumed_at: nil)
                                              .update_all(consumed_at: now, updated_at: now)
          return oauth_failure("invalid_grant", "authorization code is invalid") unless consumed_rows == 1

          session = OauthGrantSession.create!(
            oauth_client: oauth_client,
            access_recording: access_recording,
            state: authorization_code.state,
            last_used_at: now
          )

          RecordingStudio.record!(
            action: "created",
            recordable: session,
            root_recording: access_recording.root_recording,
            parent_recording: access_recording,
            actor: oauth_client
          )

          access_token_data = OauthAccessToken.generate
          session_access_token = OauthSessionAccessToken.create!(
            oauth_grant_session: session,
            token_digest: access_token_data.fetch(:digest),
            token_prefix: access_token_data.fetch(:prefix),
            expires_at: now + ACCESS_TOKEN_TTL_SECONDS
          )

          RecordingStudio.record!(
            action: "created",
            recordable: session_access_token,
            root_recording: access_recording.root_recording,
            parent_recording: session.recording,
            actor: oauth_client
          )

          refresh_token_data = OauthRefreshTokenValue.generate
          refresh_token = OauthRefreshToken.create!(
            oauth_grant_session: session,
            token_digest: refresh_token_data.fetch(:digest),
            token_prefix: refresh_token_data.fetch(:prefix),
            expires_at: now + REFRESH_TOKEN_TTL_SECONDS
          )

          RecordingStudio.record!(
            action: "created",
            recordable: refresh_token,
            root_recording: access_recording.root_recording,
            parent_recording: session.recording,
            actor: oauth_client
          )

          payload = {
            access_token: access_token_data.fetch(:token),
            token_type: "Bearer",
            expires_in: ACCESS_TOKEN_TTL_SECONDS,
            refresh_token: refresh_token_data.fetch(:token),
            created_at: now.to_i
          }
        end
        # rubocop:enable Metrics/BlockLength

        success(payload)
      rescue ActiveRecord::ActiveRecordError => e
        failure(e)
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity

      def oauth_failure(code, description)
        failure({ error: code, error_description: description })
      end

      def secure_compare(left, right)
        return false if left.blank? || right.blank?
        return false unless left.bytesize == right.bytesize

        ActiveSupport::SecurityUtils.secure_compare(left, right)
      end

      def service_args
        {
          grant_type: grant_type,
          client_id_present: client_id.present?,
          code_present: code.present?,
          redirect_uri_present: redirect_uri.present?,
          code_verifier_present: code_verifier.present?
        }
      end
    end
  end
end
