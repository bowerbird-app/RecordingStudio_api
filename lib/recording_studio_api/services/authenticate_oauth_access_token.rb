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
        OauthAccessToken.valid_format?(token) || registered_token_authenticator_accepts_format?(token)
      end

      def resolve_authenticated_entities(token)
        resolve_api_access_token(token) ||
          resolve_registered_token_authenticator(token) ||
          [nil, nil]
      end

      def token_record_active?(token_record)
        token_record&.active_for_authentication? || false
      end

      def update_last_used!(credential, token_record)
        touch_last_used_at!(token_record)
        touch_last_used_at!(credential)
      end

      def active_recording_exists_for?(recordable_type, recordable_id)
        RecordingStudio::Recording.unscoped.exists?(
          recordable_type: recordable_type,
          recordable_id: recordable_id,
          trashed_at: nil
        )
      end

      def resolve_api_access_token(token)
        provided_digest = OauthAccessToken.digest(token)
        access_token = ApiAccessToken.includes(credential: :api_client).find_by(token_digest: provided_digest)
        return if access_token.nil?
        return [nil, nil] unless active_recording_exists_for?("RecordingStudioApi::ApiAccessToken", access_token.id)

        credential = access_token.credential
        return [nil, nil] if credential.nil?
        return [nil, nil] unless active_recording_exists_for?("RecordingStudioApi::ApiCredential", credential.id)

        [credential, access_token]
      end

      def resolve_registered_token_authenticator(token)
        RecordingStudioApi.token_authenticators.each do |authenticator|
          resolved = authenticator.call(token: token)
          next if resolved.nil?

          credential, token_record = normalize_registered_authenticator_response(resolved)
          next if credential.nil?

          return [credential, token_record || credential]
        end

        nil
      end

      def normalize_registered_authenticator_response(resolved)
        if resolved.is_a?(Hash)
          [resolved[:credential], resolved[:token_record]]
        elsif resolved.respond_to?(:to_ary)
          pair = resolved.to_ary
          [pair[0], pair[1]]
        else
          [resolved, nil]
        end
      end

      def registered_token_authenticator_accepts_format?(token)
        RecordingStudioApi.token_authenticators.any? do |authenticator|
          authenticator.respond_to?(:valid_format?) && authenticator.valid_format?(token)
        end
      end

    end
  end
end