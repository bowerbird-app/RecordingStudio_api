# frozen_string_literal: true

require "digest"
require "securerandom"

module RecordingStudioApi
  module Services
    class AuthorizeOauthClient < BaseService
      CODE_CHALLENGE_METHOD = "S256"
      CODE_TTL_SECONDS = 600

      def initialize(response_type:, client_id:, redirect_uri:, code_challenge:, code_challenge_method:, access_recording_id:, state: nil)
        @response_type = response_type
        @client_id = client_id
        @redirect_uri = redirect_uri
        @code_challenge = code_challenge
        @code_challenge_method = code_challenge_method
        @access_recording_id = access_recording_id
        @state = state
      end

      private

      attr_reader :response_type, :client_id, :redirect_uri, :code_challenge, :code_challenge_method, :access_recording_id, :state

      def perform
        return oauth_failure("unsupported_response_type", "response_type must be code") unless response_type == "code"
        return oauth_failure("invalid_request", "client_id is required") if client_id.blank?
        return oauth_failure("invalid_request", "redirect_uri is required") if redirect_uri.blank?
        return oauth_failure("invalid_request", "code_challenge is required") if code_challenge.blank?
        return oauth_failure("invalid_request", "access_recording_id is required") if access_recording_id.blank?
        return oauth_failure("invalid_request", "code_challenge_method must be #{CODE_CHALLENGE_METHOD}") unless code_challenge_method == CODE_CHALLENGE_METHOD
        return oauth_failure("invalid_request", "code_challenge format is invalid") unless valid_code_challenge?(code_challenge)

        oauth_client = OauthClient.find_by(client_identifier: client_id, active: true, public_client: true)
        return oauth_failure("invalid_client", "client authentication failed") if oauth_client.nil?
        return oauth_failure("invalid_request", "redirect_uri is invalid") unless oauth_client.redirect_uri == redirect_uri

        access_recording = active_access_recording(access_recording_id)
        return oauth_failure("invalid_scope", "access recording is invalid") if access_recording.nil?

        code_data = generate_authorization_code

        OauthAuthorizationCode.transaction do
          authorization_code = OauthAuthorizationCode.create!(
            oauth_client: oauth_client,
            access_recording: access_recording,
            code_digest: code_data.fetch(:digest),
            code_prefix: code_data.fetch(:prefix),
            code_challenge: code_challenge,
            code_challenge_method: code_challenge_method,
            redirect_uri: redirect_uri,
            state: state,
            expires_at: Time.current + CODE_TTL_SECONDS
          )

          RecordingStudio.record!(
            action: "created",
            recordable: authorization_code,
            root_recording: access_recording.root_recording,
            parent_recording: access_recording,
            actor: access_recording.recordable
          )
        end

        success(
          {
            code: code_data.fetch(:code),
            redirect_uri: redirect_uri,
            state: state
          }
        )
      rescue ActiveRecord::ActiveRecordError => e
        failure(e)
      end

      def oauth_failure(code, description)
        failure({ error: code, error_description: description })
      end

      def valid_code_challenge?(value)
        return false unless value.match?(/\A[A-Za-z0-9\-._~]{43,128}\z/)

        true
      end

      def active_access_recording(recording_id)
        RecordingStudio::Recording.unscoped.find_by(
          id: recording_id,
          recordable_type: "RecordingStudio::Access",
          trashed_at: nil
        )
      end

      def generate_authorization_code
        code = SecureRandom.urlsafe_base64(48, false)
        {
          code: code,
          digest: Digest::SHA256.hexdigest(code),
          prefix: code.first(8)
        }
      end

      def service_args
        {
          response_type: response_type,
          client_id_present: client_id.present?,
          redirect_uri_present: redirect_uri.present?,
          code_challenge_method: code_challenge_method,
          access_recording_id: access_recording_id
        }
      end
    end
  end
end