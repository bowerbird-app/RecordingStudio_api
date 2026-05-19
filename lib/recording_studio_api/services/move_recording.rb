# frozen_string_literal: true

module RecordingStudioApi
  module Services
    class MoveRecording
      def self.call(context)
        new(context).call
      end

      def initialize(context)
        @context = context
      end

      def call
        destination = find_destination!
        raise UnsupportedActionError, "Move is not supported for #{context.recording.recordable_type}" unless context.recording.respond_to?(:move_to!)

        context.recording.move_to!(
          new_parent: destination,
          actor: context.api_client,
          metadata: metadata
        )
        context.recording.reload
      end

      private

      attr_reader :context

      def find_destination!
        destination_id = context.params[:parent_id].presence || context.params[:destination_id].presence || context.params[:new_parent_id].presence
        raise UnsupportedActionError, "parent_id is required for move" if destination_id.blank?

        destination = RecordingStudioApi::AccessibleRecordingScope.new(
          scope_recording: context.scope_recording,
          access_recording: context.access_recording
        ).relation.find_by(id: destination_id)
        raise NotFoundError, "Destination recording was not found in this API scope" if destination.nil?

        destination
      end

      def metadata
        {
          api_action: "move",
          api_client_id: context.api_client.id,
          api_credential_id: context.credential.id
        }
      end
    end
  end
end
