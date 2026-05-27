# frozen_string_literal: true

module RecordingStudioApi
  module Services
    class RevokeOauthGrantSession < BaseService
      def initialize(oauth_grant_session_id:, authorization_header:)
        @oauth_grant_session_id = oauth_grant_session_id
        @authorization_header = authorization_header
      end

      private

      attr_reader :oauth_grant_session_id, :authorization_header

      def perform
        return oauth_failure("invalid_request", "oauth_grant_session_id is required") if oauth_grant_session_id.blank?

        auth_result = AuthenticateOauthAccessToken.call(authorization_header: authorization_header)
        return failure(auth_result.error) if auth_result.failure?

        caller = auth_result.value
        session = OauthGrantSession.includes(:access_recording).find_by(id: oauth_grant_session_id)
        return oauth_failure("invalid_request", "oauth grant session was not found") if session.nil?

        return oauth_failure("invalid_scope", "not authorized to revoke this oauth grant session") unless authorized_to_revoke?(caller, session)

        session.revoke_family!
        success(nil)
      rescue ActiveRecord::ActiveRecordError => e
        failure(e)
      end

      def authorized_to_revoke?(caller, session)
        access_management_policy(caller).can_manage_root_recording?(session.access_recording.root_recording)
      end

      def oauth_failure(code, description)
        failure({ error: code, error_description: description })
      end

      def service_args
        {
          oauth_grant_session_id: oauth_grant_session_id,
          authorization_header_present: authorization_header.present?
        }
      end

      def access_management_policy(caller)
        @access_management_policy ||= {}
        actor = caller.access_recording&.recordable&.respond_to?(:actor) ? caller.access_recording.recordable.actor : nil
        @access_management_policy[caller.object_id] ||= RecordingStudioApi::AccessManagementPolicy.new(actor: actor)
      end
    end
  end
end
