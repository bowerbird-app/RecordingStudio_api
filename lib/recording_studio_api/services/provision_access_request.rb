# frozen_string_literal: true

module RecordingStudioApi
  module Services
    class ProvisionAccessRequest < BaseService
      def initialize(root_recording:, actor:, role:, api_client_name:, expires_at: nil)
        @root_recording = root_recording
        @actor = actor
        @role = role
        @api_client_name = api_client_name
        @expires_at = expires_at
      end

      private

      attr_reader :root_recording, :actor, :role, :api_client_name, :expires_at

      def perform
        return failure("Root recording is required") if root_recording.nil?
        return failure("Root recording must be a top-level API resource") unless valid_root_recording?
        return failure("Actor is required") if actor.nil?
        return failure("Access role is required") if role.blank?
        return failure("API client name is required") if api_client_name.blank?
        return failure("Actor is not authorized to manage API access for this root recording") unless access_management_policy.can_manage_root_recording?(root_recording)

        payload = nil

        ApiCredential.transaction do
          access_recording = create_access_recording!
          provision_result = ProvisionApiClient.call(
            access_recording: access_recording,
            name: api_client_name,
            expires_at: expires_at
          )

          raise RecordingStudioApi::Error, provision_result.error if provision_result.failure?

          payload = provision_result.value.merge(
            root_recording: root_recording,
            access_recording: access_recording
          )
        end

        success(payload)
      rescue ActiveRecord::ActiveRecordError, RecordingStudioApi::Error => e
        failure(e)
      end

      def valid_root_recording?
        root_recording.parent_recording_id.nil? &&
          RecordingStudioApi.api_recordable_types.include?(root_recording.recordable_type)
      end

      def create_access_recording!
        access = RecordingStudio::Access.create!(actor: actor, role: role)

        RecordingStudio.record!(
          action: "created",
          recordable: access,
          root_recording: root_recording,
          parent_recording: root_recording,
          actor: actor
        ).recording
      end

      def service_args
        {
          root_recording_id: root_recording&.id,
          actor_id: actor&.id,
          actor_type: actor&.class&.name,
          role: role,
          api_client_name: api_client_name,
          expires_at: expires_at
        }
      end

      def access_management_policy
        @access_management_policy ||= RecordingStudioApi::AccessManagementPolicy.new(actor: actor)
      end
    end
  end
end