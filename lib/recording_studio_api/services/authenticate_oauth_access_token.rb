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
        if access_token.present?
          return [nil, nil] unless active_recording_exists_for?("RecordingStudioApi::ApiAccessToken", access_token.id)

          credential = access_token.credential
          return [nil, nil] if credential.nil?
          return [nil, nil] unless active_recording_exists_for?("RecordingStudioApi::ApiCredential", credential.id)

          return [credential, access_token]
        end

        mobile_token = OauthSessionAccessToken.includes(oauth_grant_session: :oauth_client).find_by(token_digest: provided_digest)
        return [nil, nil] if mobile_token.nil?
        return [nil, nil] unless active_recording_exists_for?("RecordingStudioApi::OauthSessionAccessToken", mobile_token.id)

        grant_session = mobile_token.oauth_grant_session
        return [nil, nil] if grant_session.nil?
        return [nil, nil] unless active_recording_exists_for?("RecordingStudioApi::OauthGrantSession", grant_session.id)

        [grant_session, mobile_token]
      end

      def token_record_active?(token_record)
        token_record&.active_for_authentication? || false
      end

      def update_last_used!(credential, token_record)
        token_record&.update_column(:last_used_at, Time.current)
        credential.update_column(:last_used_at, Time.current)
      end

      def active_recording_exists_for?(recordable_type, recordable_id)
        RecordingStudio::Recording.unscoped.exists?(
          recordable_type: recordable_type,
          recordable_id: recordable_id,
          trashed_at: nil
        )
      end

    end
  end
end