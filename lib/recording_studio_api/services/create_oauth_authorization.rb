# frozen_string_literal: true

module RecordingStudioApi
  module Services
    class CreateOauthAuthorization < BaseService
      def initialize(oauth_client:, manager_actor:, access_recording:, role:, redirect_uri:, code_challenge:, code_challenge_method: Pkce::S256)
        @oauth_client = oauth_client
        @manager_actor = manager_actor
        @access_recording = access_recording
        @role = role.to_s
        @redirect_uri = redirect_uri.to_s
        @code_challenge = code_challenge.to_s.presence
        @code_challenge_method = code_challenge_method.to_s.presence
      end

      private

      attr_reader :oauth_client, :manager_actor, :access_recording, :role, :redirect_uri, :code_challenge, :code_challenge_method

      def perform
        validation = validate_request
        return validation unless validation == true

        payload = nil
        OauthAuthorization.transaction do
          authorization = OauthAuthorization.create!(
            oauth_client: oauth_client,
            manager_actor: manager_actor,
            manager_access_recording: access_recording,
            role: role
          )

          grant_result = RecordingStudioAccessible.grant_access(
            recording: access_point_recording,
            actor: authorization,
            role: role,
            manager_actor: manager_actor
          )
          raise RecordingStudioApi::Error, grant_result.error if grant_result.failure?

          granted_access_recording = grant_result.value
          authorization.update_columns(
            access_recording_id: granted_access_recording.id,
            updated_at: Time.current
          )
          authorization.association(:access_recording).reset

          code_data = AuthorizationCode.generate
          OauthAuthorizationCode.create!(
            oauth_authorization: authorization,
            code_digest: code_data.fetch(:digest),
            redirect_uri: redirect_uri,
            code_challenge: code_challenge,
            code_challenge_method: code_challenge_method,
            expires_at: Time.current + authorization_code_ttl
          )

          payload = {
            authorization: authorization.reload,
            code: code_data.fetch(:token),
            access_recording: granted_access_recording
          }
        end

        success(payload)
      rescue RecordingStudioApi::Error, ActiveRecord::ActiveRecordError => e
        failure(e)
      end

      def validate_request
        return failure("OAuth client is required") if oauth_client.nil?
        return failure("OAuth client is revoked") if oauth_client.revoked?
        return failure("Manager is required") if manager_actor.nil?
        return failure("Access recording is required") if access_recording.nil?
        return failure("Access recording must point to RecordingStudio::Access") if access_recording.recordable_type != "RecordingStudio::Access"
        return failure("Role is invalid") unless OauthAuthorization::ROLES.include?(role)
        return failure("Redirect URI is invalid") unless oauth_client.redirect_uri_allowed?(redirect_uri)
        return failure("PKCE S256 is required") if oauth_client.public? && (code_challenge.blank? || code_challenge_method != Pkce::S256)
        return failure("PKCE method must be S256") if code_challenge_method.present? && code_challenge_method != Pkce::S256
        return failure("Access point recording is required") if access_point_recording.nil?
        return failure("Requested role exceeds the manager's access") unless can_assign_requested_role?

        true
      end

      def can_assign_requested_role?
        AccessManagementPolicy.new(actor: manager_actor).can_assign_role?(access_point_recording, role)
      end

      def access_point_recording
        @access_point_recording ||= access_recording.parent_recording || access_recording.root_recording
      end

      def authorization_code_ttl
        RecordingStudioApi.configuration.authorization_code_ttl.presence || 10.minutes
      end

      def service_args
        {
          oauth_client_id: oauth_client&.id,
          manager_actor_type: manager_actor&.class&.name,
          manager_actor_id: manager_actor&.id,
          access_recording_id: access_recording&.id,
          role: role
        }
      end
    end
  end
end
