# frozen_string_literal: true

module RecordingStudioApi
  module Services
    class RefreshOauthAccessToken < BaseService
      ACCESS_TOKEN_TTL_SECONDS = 900
      REFRESH_TOKEN_TTL_SECONDS = 2_592_000

      def initialize(grant_type:, client_id:, refresh_token:)
        @grant_type = grant_type
        @client_id = client_id
        @refresh_token = refresh_token
      end

      private

      attr_reader :grant_type, :client_id, :refresh_token

      # rubocop:disable Metrics/AbcSize
      def perform
        return oauth_failure("unsupported_grant_type", "grant_type must be refresh_token") unless grant_type == "refresh_token"
        return oauth_failure("invalid_request", "client_id is required") if client_id.blank?
        return oauth_failure("invalid_request", "refresh_token is required") if refresh_token.blank?
        return oauth_failure("invalid_grant", "refresh token format is invalid") unless OauthRefreshTokenValue.valid_format?(refresh_token)

        oauth_client = OauthClient.find_by(client_identifier: client_id, active: true, public_client: true)
        return oauth_failure("invalid_client", "client authentication failed") if oauth_client.nil?

        payload = nil
        now = Time.current
        refresh_digest = OauthRefreshTokenValue.digest(refresh_token)

        OauthRefreshToken.transaction do
          refresh_record = OauthRefreshToken.lock.find_by(token_digest: refresh_digest)
          return oauth_failure("invalid_grant", "refresh token is invalid") if refresh_record.nil?

          session = refresh_record.oauth_grant_session
          return oauth_failure("invalid_grant", "refresh token is invalid") if session.nil? || session.oauth_client_id != oauth_client.id

          if refresh_record.consumed_at.present?
            session.revoke_family!
            return oauth_failure("invalid_grant", "refresh token was already used")
          end

          return oauth_failure("invalid_grant", "refresh token is inactive") unless refresh_record.active_for_authentication?

          access_recording = session.access_recording
          return oauth_failure("invalid_scope", "access recording is invalid") if access_recording.nil? || access_recording.trashed_at.present?

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
          next_refresh = OauthRefreshToken.create!(
            oauth_grant_session: session,
            previous_refresh_token: refresh_record,
            token_digest: refresh_token_data.fetch(:digest),
            token_prefix: refresh_token_data.fetch(:prefix),
            expires_at: now + REFRESH_TOKEN_TTL_SECONDS
          )

          RecordingStudio.record!(
            action: "created",
            recordable: next_refresh,
            root_recording: access_recording.root_recording,
            parent_recording: session.recording,
            actor: oauth_client
          )

          consumed_rows = OauthRefreshToken.where(id: refresh_record.id, consumed_at: nil).update_all(
            consumed_at: now,
            last_used_at: now,
            replaced_by_id: next_refresh.id,
            updated_at: now
          )
          return oauth_failure("invalid_grant", "refresh token was already used") unless consumed_rows == 1

          session.update_columns(last_used_at: now, updated_at: now)

          payload = {
            access_token: access_token_data.fetch(:token),
            token_type: "Bearer",
            expires_in: ACCESS_TOKEN_TTL_SECONDS,
            refresh_token: refresh_token_data.fetch(:token),
            created_at: now.to_i
          }
        end

        success(payload)
      rescue ActiveRecord::ActiveRecordError => e
        failure(e)
      end
      # rubocop:enable Metrics/AbcSize

      def oauth_failure(code, description)
        failure({ error: code, error_description: description })
      end

      def service_args
        {
          grant_type: grant_type,
          client_id_present: client_id.present?,
          refresh_token_present: refresh_token.present?
        }
      end
    end
  end
end
