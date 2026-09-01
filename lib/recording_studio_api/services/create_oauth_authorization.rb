# frozen_string_literal: true

module RecordingStudioApi
  module Services
    class CreateOauthAuthorization < BaseService
      ACCESS_GONE_MESSAGE = "That access is gone. Connect again."
      ROLE_CHANGED_MESSAGE = "Your access changed. Connect again."

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
          authorization = existing_authorization_for_node
          if authorization
            prepare_reopen!(authorization)
          else
            authorization = OauthAuthorization.create!(
              oauth_client: oauth_client,
              manager_actor: manager_actor,
              manager_access_recording: access_recording,
              role: role
            )
          end

          grant_result = RecordingStudioAccessible.grant_access(
            recording: access_point_recording,
            actor: authorization,
            role: role,
            manager_actor: manager_actor,
            depends_on: access_recording
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
        client_validation = validate_client
        return client_validation unless client_validation == true

        return failure("Manager is required") if manager_actor.nil?
        return failure("Access recording is required") if access_recording.nil?
        return failure("Access recording must point to RecordingStudio::Access") if access_recording.recordable_type != "RecordingStudio::Access"
        return failure("Role is invalid") unless OauthAuthorization::ROLES.include?(role)
        return failure("Access point recording is required") if access_point_recording.nil?
        return failure(ACCESS_GONE_MESSAGE) unless manager_access_present?
        return failure(ROLE_CHANGED_MESSAGE) unless can_assign_requested_role?

        true
      end

      def validate_client
        return failure("OAuth client is required") if oauth_client.nil?
        return failure("OAuth client is revoked") if oauth_client.revoked?
        return failure("Redirect URI is invalid") unless oauth_client.redirect_uri_allowed?(redirect_uri)
        return failure("PKCE S256 is required") if oauth_client.public? && (code_challenge.blank? || code_challenge_method != Pkce::S256)
        return failure("PKCE method must be S256") if code_challenge_method.present? && code_challenge_method != Pkce::S256

        true
      end

      def existing_authorization_for_node
        OauthAuthorization.lock.find_by(
          oauth_client: oauth_client,
          manager_actor: manager_actor,
          manager_access_recording: access_recording
        )
      end

      def prepare_reopen!(authorization)
        time = Time.current
        granted = authorization.access_recording
        granted.update_columns(trashed_at: time, updated_at: time) if granted && granted.trashed_at.nil?
        ApiAccessToken.where(oauth_authorization_id: authorization.id, revoked_at: nil)
                      .update_all(revoked_at: time, updated_at: time)
        OauthRefreshToken.where(oauth_authorization_id: authorization.id, revoked_at: nil)
                         .update_all(revoked_at: time, updated_at: time)
        authorization.update!(role: role, revoked_at: nil)
      end

      def manager_access_present?
        return false if access_recording.trashed_at.present?
        return false unless access_recording.recordable.is_a?(RecordingStudio::Access)

        true
      end

      def can_assign_requested_role?
        OauthAuthorization.role_at_or_below?(role, access_recording.recordable.role)
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
