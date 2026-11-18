# frozen_string_literal: true

module RecordingStudioApi
  module Services
    # Trashes an API client's access grant and the recordings under it.
    # Credential revocation stays with the caller so authentication fails
    # immediately. The grant is not destroyed: child recordings, including
    # trashed ones, still hang off it, and core refuses that destroy.
    class RetireApiAccess < RecordingStudio::Services::BaseService
      def initialize(access_recording:, actor:)
        @access_recording = access_recording
        @actor = actor
      end

      private

      attr_reader :access_recording, :actor

      def perform
        return failure("Access recording is required") if access_recording.nil?
        return failure("Actor is required") if actor.nil?
        return failure("Access recording must point to RecordingStudio::Access") unless access_recording.recordable_type == "RecordingStudio::Access"

        anchors = [access_recording.parent_recording].compact
        anchors.concat(RecordingStudioAccessible::LastAdminGuard.dependent_parent_recordings(access_recording))
        RecordingStudioAccessible::LastAdminGuard.protect!(recordings: anchors) do
          access_recording.recording_studio_trashable_trash!(
            actor: actor,
            metadata: { source: "recording_studio_api", reason: "api_client_retired" }
          )
        end

        success(access_recording)
      rescue RecordingStudioAccessible::LastAdminError, ArgumentError => e
        failure(e.message)
      end

      def service_args
        {
          access_recording_id: access_recording&.id,
          actor_id: actor&.id,
          actor_type: actor&.class&.name
        }
      end
    end
  end
end
