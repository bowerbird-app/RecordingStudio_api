# frozen_string_literal: true

module RecordingStudioApi
  module Services
    class IssueOauthAccessToken < BaseService
      SUPPORTED_GRANT_TYPES = %w[client_credentials authorization_code refresh_token].freeze
      DUMMY_CLIENT_SECRET = "recording-studio-api.oauth.dummy-client-secret"

      def initialize(grant_type:, client_id:, client_secret: nil, api: :public, code: nil, redirect_uri: nil, code_verifier: nil, refresh_token: nil, resource: nil)
        @grant_type = grant_type.to_s
        @client_id = client_id.to_s
        @client_secret = client_secret.to_s
        @api_key = RecordingStudioApi.configuration.fetch_api(api).name
        @code = code.to_s.presence
        @redirect_uri = redirect_uri.to_s.presence
        @code_verifier = code_verifier.to_s.presence
        @refresh_token = refresh_token.to_s.presence
        @resource = resource.to_s.presence
      end

      private

      attr_reader :grant_type, :client_id, :client_secret, :api_key, :code, :redirect_uri, :code_verifier, :refresh_token, :resource

      def perform
        return oauth_failure("invalid_request", "grant_type is required") if grant_type.blank?
        return oauth_failure("unsupported_grant_type", "grant_type must be #{SUPPORTED_GRANT_TYPES.join(', ')}") unless SUPPORTED_GRANT_TYPES.include?(grant_type)
        return oauth_failure("invalid_target", "resource does not match this API") unless resource_matches_api?

        case grant_type
        when "client_credentials"
          issue_client_credentials
        when "authorization_code"
          issue_authorization_code
        when "refresh_token"
          issue_refresh_token
        end
      rescue ActiveRecord::ActiveRecordError, RecordingStudioApi::Error
        failure(OauthErrorMapper.server_error_payload)
      end

      def issue_client_credentials
        return oauth_failure("invalid_request", "client_id is required") if client_id.blank?
        return oauth_failure("invalid_request", "client_secret is required") if client_secret.blank?

        credential = ApiCredential.joins(:api_client)
                                  .merge(ApiClient.where(api_key: api_key))
                                  .find_by(token_public_id: client_id)
        return oauth_failure("invalid_client", "client authentication failed") unless authenticate_machine_client?(credential)

        token_data = OauthAccessToken.generate
        expires_at = access_token_expiry
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

        success(machine_token_payload(access_token, token_data, credential))
      end

      def issue_authorization_code
        client_result = AuthenticateOauthClient.call(
          client_id: client_id,
          client_secret: client_secret,
          api: api_key,
          allow_public: true
        )
        return client_result if client_result.failure?

        client = client_result.value
        return oauth_failure("invalid_request", "code is required") if code.blank?
        return oauth_failure("invalid_request", "redirect_uri is required") if redirect_uri.blank?
        return oauth_failure("invalid_grant", "redirect_uri does not match") unless client.redirect_uri_allowed?(redirect_uri)

        code_record = AuthorizationCode.find_by_token(OauthAuthorizationCode.lock, code)
        if code_record.nil?
          perform_dummy_pkce_compare
          return oauth_failure("invalid_grant", "authorization code is invalid")
        end

        if code_record.used?
          VoidOauthAuthorization.call(authorization: code_record.oauth_authorization)
          return oauth_failure("invalid_grant", "authorization code has already been used")
        end

        return oauth_failure("invalid_grant", "authorization code has expired") if code_record.expired?
        return oauth_failure("invalid_grant", "authorization code does not belong to this client") unless code_record.oauth_authorization.oauth_client_id == client.id
        return oauth_failure("invalid_grant", "redirect_uri does not match") unless code_record.redirect_uri == redirect_uri
        return oauth_failure("invalid_grant", "authorization is no longer valid") unless code_record.oauth_authorization.active?

        pkce_result = validate_pkce!(client, code_record)
        return pkce_result if pkce_result != true

        code_record.mark_used!
        issue_delegated_tokens(code_record.oauth_authorization)
      end

      def issue_refresh_token
        client_result = AuthenticateOauthClient.call(
          client_id: client_id,
          client_secret: client_secret,
          api: api_key,
          allow_public: true
        )
        return client_result if client_result.failure?

        client = client_result.value
        return oauth_failure("invalid_request", "refresh_token is required") if refresh_token.blank?

        stored = RefreshToken.find_by_token(OauthRefreshToken.lock, refresh_token)
        return oauth_failure("invalid_grant", "refresh token is invalid") if stored.nil?
        return oauth_failure("invalid_grant", "refresh token is invalid") unless stored.oauth_authorization.oauth_client_id == client.id
        return oauth_failure("invalid_grant", "refresh token has been revoked") if stored.revoked?
        return oauth_failure("invalid_grant", "refresh token has expired") if stored.expired?

        authorization = stored.oauth_authorization
        return oauth_failure("invalid_grant", "authorization is no longer valid") unless authorization.active?

        stored.revoke!
        issue_delegated_tokens(authorization, replacing: stored)
      end

      def issue_delegated_tokens(authorization, replacing: nil)
        access_data = OauthAccessToken.generate
        refresh_data = RefreshToken.generate
        expires_at = access_token_expiry
        refresh_expires_at = refresh_token_expiry
        access_token = nil
        refresh_record = nil

        OauthAuthorization.transaction do
          access_token = ApiAccessToken.create!(
            oauth_authorization: authorization,
            token_digest: access_data.fetch(:digest),
            token_prefix: access_data.fetch(:prefix),
            expires_at: expires_at
          )
          refresh_record = OauthRefreshToken.create!(
            oauth_authorization: authorization,
            token_digest: refresh_data.fetch(:digest),
            token_prefix: refresh_data.fetch(:prefix),
            expires_at: refresh_expires_at
          )
          replacing.update_columns(replaced_by_id: refresh_record.id, updated_at: Time.current) if replacing.present?
        end

        success(
          {
            access_token: access_data.fetch(:token),
            refresh_token: refresh_data.fetch(:token),
            token_type: "Bearer",
            expires_in: (expires_at - Time.current).to_i,
            created_at: access_token.created_at.to_i
          }
        )
      end

      def validate_pkce!(client, code_record)
        if client.public? || code_record.code_challenge.present?
          return oauth_failure("invalid_request", "code_verifier is required") if code_verifier.blank?
          return oauth_failure("invalid_request", "PKCE method must be S256") if code_record.code_challenge_method.present? && code_record.code_challenge_method != Pkce::S256
          return oauth_failure("invalid_grant", "PKCE verification failed") unless Pkce.s256_matches?(code_verifier, code_record.code_challenge)
        end

        true
      end

      def perform_dummy_pkce_compare
        Pkce.s256_matches?("a" * 43, Pkce.s256_challenge("a" * 43))
        nil
      end

      def authenticate_machine_client?(credential)
        expected_digest = credential&.token_digest.presence || dummy_client_secret_digest
        secret_matches = Token.digest_matches?(expected_digest, client_secret)
        TokenDigest.rehash_if_legacy!(credential, client_secret) if secret_matches && credential.present?

        return false if credential.blank? || !secret_matches

        unless credential.active_for_authentication?
          credential.revoke_tokens_on_expiry!
          return false
        end

        true
      end

      def dummy_client_secret_digest
        Token.digest(DUMMY_CLIENT_SECRET)
      end

      def resource_matches_api?
        return true if resource.blank?

        resource == api_key || resource == "recording_studio_api:#{api_key}"
      end

      def access_token_expiry
        ttl = RecordingStudioApi::ApiRuntimePolicy.for(api_key).access_token_ttl
        Time.current + (ttl.presence || 1.hour)
      end

      def refresh_token_expiry
        ttl = RecordingStudioApi.configuration.refresh_token_ttl
        Time.current + (ttl.presence || 30.days)
      end

      def machine_token_payload(access_token, token_data, credential)
        {
          access_token: token_data.fetch(:token),
          token_type: "Bearer",
          expires_in: (access_token.expires_at - Time.current).to_i,
          created_at: access_token.created_at.to_i,
          api_client_id: credential.api_client_id
        }
      end

      def oauth_failure(code, description)
        failure({ error: code, error_description: description })
      end

      def service_args
        {
          grant_type: grant_type,
          api_key: api_key,
          client_id_present: client_id.present?,
          client_secret_present: client_secret.present?,
          code_present: code.present?,
          refresh_token_present: refresh_token.present?
        }
      end
    end
  end
end
