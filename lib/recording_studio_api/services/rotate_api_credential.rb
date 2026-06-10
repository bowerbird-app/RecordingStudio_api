# frozen_string_literal: true

module RecordingStudioApi
  module Services
    class RotateApiCredential < BaseService
      def initialize(api_client:, actor:, expires_at: nil)
        @api_client = api_client
        @actor = actor
        @expires_at = expires_at
      end

      private

      attr_reader :api_client, :actor, :expires_at

      def perform
        return failure("API client is required") if api_client.nil?
        return failure("Actor is required") if actor.nil?
        return failure("API client access recording is missing") if api_client.access_recording.nil?
        return failure("Actor is not authorized to manage API access for this recording") unless access_management_policy.can_manage_recording?(access_point_recording)

        token = Token.generate
        payload = nil

        ApiCredential.transaction do
          previous_credential = latest_credential
          raise RecordingStudioApi::Error, "API credential is missing" if previous_credential.nil?

          previous_credential.revoke! if previous_credential.revoked_at.nil?

          credential = ApiCredential.create!(
            api_client: api_client,
            access_recording: api_client.access_recording,
            token_public_id: token.fetch(:public_id),
            token_digest: token.fetch(:digest),
            token_prefix: token.fetch(:prefix),
            expires_at: resolved_expiry(previous_credential)
          )

          api_client_recording = api_client.recording
          raise RecordingStudioApi::Error, "API client recording is missing" if api_client_recording.nil?

          RecordingStudio.record!(
            action: "created",
            recordable: credential,
            root_recording: api_client_recording.root_recording,
            parent_recording: api_client_recording,
            actor: api_client
          )

          payload = {
            api_client: api_client,
            credential: credential,
            previous_credential: previous_credential,
            token: token.fetch(:token)
          }
        end

        success(payload)
      rescue ActiveRecord::ActiveRecordError, RecordingStudioApi::Error => e
        failure(e)
      end

      def latest_credential
        @latest_credential ||= api_client.credentials.max_by { |credential| [credential.created_at.to_i, credential.id.to_i] }
      end

      def access_point_recording
        api_client.access_recording.parent_recording || api_client.access_recording.root_recording
      end

      def resolved_expiry(previous_credential)
        return expires_at if expires_at.present?

        previous_credential.expires_at
      end

      def access_management_policy
        @access_management_policy ||= RecordingStudioApi::AccessManagementPolicy.new(actor: actor)
      end

      def service_args
        {
          api_client_id: api_client&.id,
          actor_id: actor&.id,
          actor_type: actor&.class&.name,
          expires_at: expires_at
        }
      end
    end
  end
end