# frozen_string_literal: true

module RecordingStudioApi
  module Services
    # Revoke stays with the caller so authentication fails immediately.
    # This trashes the client recording. Trashable cascades to the credential
    # and token recordings, writes trashed events, and leaves the rows.
    #
    # The Access grant stays kept. RecordingStudio::Access is Accessible's
    # model and is not Trashable here, and the trashed client recording is
    # still a child, so the grant cannot be destroyed.
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
