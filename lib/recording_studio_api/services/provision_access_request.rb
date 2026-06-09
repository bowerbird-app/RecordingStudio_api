# frozen_string_literal: true

module RecordingStudioApi
  module Services
    class ProvisionAccessRequest < BaseService
      def initialize(access_point_recording:, actor:, role:, api_client_name:, expires_at: nil)
        @access_point_recording = access_point_recording
        @actor = actor
        @role = role
        @api_client_name = api_client_name
        @expires_at = expires_at
      end

      private

      attr_reader :access_point_recording, :actor, :role, :api_client_name, :expires_at

      def perform
        return failure("Access point recording is required") if access_point_recording.nil?
        return failure("Access point recording does not allow API access") unless valid_access_point_recording?
        return failure("Actor is required") if actor.nil?
        return failure("Access role is required") if role.blank?
        return failure("API client name is required") if api_client_name.blank?
        return failure("Actor is not authorized to manage API access for this recording") unless access_management_policy.can_manage_recording?(access_point_recording)

        payload = nil

        ApiCredential.transaction do
          provision_result = ProvisionApiClient.call(
            access_point_recording: access_point_recording,
            manager_actor: actor,
            role: role,
            name: api_client_name,
            expires_at: expires_at
          )

          raise RecordingStudioApi::Error, provision_result.error if provision_result.failure?

          payload = provision_result.value.merge(
            root_recording: root_recording,
            access_point_recording: access_point_recording,
            access_recording: provision_result.value.fetch(:access_recording)
          )
        end

        success(payload)
      rescue ActiveRecord::ActiveRecordError, RecordingStudioApi::Error => e
        failure(e)
      end

      def valid_access_point_recording?
        return false unless RecordingStudioApi.api_recordable_types.include?(access_point_recording.recordable_type)
        return false unless defined?(RecordingStudioAccessible::Compatibility)

        RecordingStudioAccessible::Compatibility.access_parent_allowed?(access_point_recording)
      end

      def root_recording
        access_point_recording.root_recording || access_point_recording
      end

      def service_args
        {
          access_point_recording_id: access_point_recording&.id,
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