# frozen_string_literal: true

module RecordingStudioApi
  module Services
    class IssueOauthAccessToken < BaseService
      SUPPORTED_GRANT_TYPE = "client_credentials"
      # Fixed digest used when no credential exists so authentication always
      # performs a constant-time compare of equal-length SHA256 hex digests.
      DUMMY_CLIENT_SECRET_DIGEST = Token.digest(
        "recording-studio-api.oauth.dummy-client-secret"
      ).freeze

      def initialize(grant_type:, client_id:, client_secret:, api: :public)
        @grant_type = grant_type
        @client_id = client_id
        @client_secret = client_secret
        @api_key = RecordingStudioApi.configuration.fetch_api(api).name
      end

      private

      attr_reader :grant_type, :client_id, :client_secret, :api_key

      def perform
        return oauth_failure("invalid_request", "grant_type is required") if grant_type.blank?
        return oauth_failure("unsupported_grant_type", "grant_type must be client_credentials") unless grant_type == SUPPORTED_GRANT_TYPE
        return oauth_failure("invalid_request", "client_id is required") if client_id.blank?
        return oauth_failure("invalid_request", "client_secret is required") if client_secret.blank?

        credential = ApiCredential.joins(:api_client)
                                  .merge(ApiClient.where(api_key: api_key))
                                  .find_by(token_public_id: client_id)
        return oauth_failure("invalid_client", "client authentication failed") unless authenticate_client?(credential)

        token_data = OauthAccessToken.generate
        expires_at = resolved_expiry

        access_token = nil
        ApiAccessToken.transaction do
          access_token = ApiAccessToken.create!(
            credential: credential,
            token_digest: token_data.fetch(:digest),
            token_prefix: token_data.fetch(:prefix),
            expires_at: expires_at
          )

          credential_recording = credential.recording
          raise ActiveRecord::RecordInvalid, access_token if credential_recording.nil?

          RecordingStudio.record!(
            action: "created",
            recordable: access_token,
            root_recording: credential_recording.root_recording,
            parent_recording: credential_recording,
            actor: credential.api_client
          )
        end

        success(
          {
            access_token: token_data.fetch(:token),
            token_type: "Bearer",
            expires_in: (expires_at - Time.current).to_i,
            created_at: access_token.created_at.to_i,
            api_client_id: credential.api_client_id
          }
        )
      rescue ActiveRecord::ActiveRecordError
        failure(OauthErrorMapper.server_error_payload)
      end

      def oauth_failure(code, description)
        failure({ error: code, error_description: description })
      end

      def authenticate_client?(credential)
        provided_digest = Token.digest(client_secret)
        expected_digest = credential&.token_digest.presence || DUMMY_CLIENT_SECRET_DIGEST
        secret_matches = secure_compare(expected_digest, provided_digest)

        credential.present? && credential.active_for_authentication? && secret_matches
      end

      def secure_compare(left, right)
        return false if left.blank? || right.blank?
        return false unless left.bytesize == right.bytesize

        ActiveSupport::SecurityUtils.secure_compare(left, right)
      end

      def resolved_expiry
        ttl = RecordingStudioApi.configuration.fetch_api(api_key).access_token_ttl
        Time.current + (ttl.presence || 1.hour)
      end

      def service_args
        {
          grant_type: grant_type,
          api_key: api_key,
          client_id_present: client_id.present?,
          client_secret_present: client_secret.present?
        }
      end
    end
  end
end