# frozen_string_literal: true

module RecordingStudioApi
  module Services
    class IssueTestCredential < BaseService
      def initialize(api:, actor:, access_point_recording:, role:, name: nil)
        @api_key = RecordingStudioApi.configuration.fetch_api(api).name
        @actor = actor
        @access_point_recording = access_point_recording
        @role = role.to_s
        @name = name.presence || "Scalar #{@role} test token"
      end

      private

      attr_reader :api_key, :actor, :access_point_recording, :role, :name

      def perform
        return failure("Actor is required") if actor.nil?
        return failure("Access point recording is required") if access_point_recording.nil?
        return failure("Access role is required") if role.blank?
        return failure("Access role is invalid") unless RecordingStudio::Access.roles.key?(role)

        payload = nil
        ActiveRecord::Base.transaction do
          provision = ProvisionApiClient.call(
            api: api_key,
            access_point_recording: access_point_recording,
            manager_actor: actor,
            role: role,
            name: name
          )
          raise RecordingStudioApi::Error, provision.error if provision.failure?

          credential = provision.value.fetch(:credential)
          issued = IssueOauthAccessToken.call(
            api: api_key,
            grant_type: "client_credentials",
            client_id: credential.oauth_client_id,
            client_secret: provision.value.fetch(:token)
          )
          raise RecordingStudioApi::Error, oauth_error_message(issued.error) if issued.failure?

          access_token = issued.value.fetch(:access_token)
          access_token_record = ApiAccessToken.find_by!(token_digest: OauthAccessToken.digest(access_token))
          payload = provision.value.merge(
            access_token: access_token,
            access_token_record: access_token_record,
            scope_recording: access_point_recording,
            root_recording: access_point_recording.root_recording || access_point_recording,
            role: provision.value.fetch(:access_recording).recordable.role.to_s,
            api: api_key
          )
        end

        success(payload)
      rescue ActiveRecord::ActiveRecordError, RecordingStudioApi::Error => e
        failure(e.message)
      end

      def oauth_error_message(error)
        return error.to_s unless error.is_a?(Hash)

        [error[:error], error[:error_description]].compact.join(": ")
      end
    end
  end
end