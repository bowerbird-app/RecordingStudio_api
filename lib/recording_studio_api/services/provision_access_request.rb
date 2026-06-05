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
        unless access_management_policy.can_manage_recording?(access_point_recording)
          return failure("Actor is not authorized to manage API access for this recording")
        end

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
            access_point_recording: access_point_recording,
            access_recording: access_recording
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

      def create_access_recording!
        result = RecordingStudioAccessible.grant_access(
          recording: access_point_recording,
          actor: actor,
          role: effective_role,
          manager_actor: actor
        )

        raise RecordingStudioApi::Error, result.error if result.failure?

        result.value
      end

      def effective_role
        existing_role = existing_access_recording&.recordable&.role.to_s.presence
        requested_role = role.to_s
        return requested_role if existing_role.blank?

        [existing_role, requested_role].max_by { |value| RecordingStudio::Access.roles.fetch(value) }
      end

      def existing_access_recording
        @existing_access_recording ||= RecordingStudioAccessible.access_recordings_for_actor(
          recording: access_point_recording,
          actor: actor
        ).first
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