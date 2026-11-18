# frozen_string_literal: true

module RecordingStudioApi
  module Services
    # Revoke stays with the caller so authentication fails immediately.
    # This trashes the client recording. Trashable cascades to the credential
    # and token recordings, writes trashed events, and leaves the rows.
    #
    # The Access grant stays. RecordingStudio::Access is Accessible's model
    # and is not Trashable here. RevokeRecordingAccess destroys the grant, and
    # core refuses that destroy while the client recording is still a child,
    # including after it is trashed. When no child remains, the grant is
    # removed through Accessible.
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

        client_recording = client_recording_for_grant
        return failure("API client recording is missing") if client_recording.nil?

        client_recording.recording_studio_trashable_trash!(
          actor: actor,
          metadata: { source: "recording_studio_api", reason: "api_client_retired" }
        )
        remove_grant_when_childless

        success(access_recording)
      rescue ArgumentError => e
        failure(e.message)
      end

      def client_recording_for_grant
        client = access_recording.recordable&.actor
        return unless client.is_a?(RecordingStudioApi::ApiClient)

        RecordingStudio::Recording.unscoped.find_by(
          recordable: client,
          parent_recording_id: access_recording.id
        )
      end

      def remove_grant_when_childless
        return if access_recording.child_recordings.exists?

        revoked = RecordingStudioAccessible.revoke_access(
          recording: access_recording.parent_recording,
          access_recording: access_recording,
          manager_actor: actor
        )
        return if revoked.success?

        raise ArgumentError, revoked.error.to_s
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
