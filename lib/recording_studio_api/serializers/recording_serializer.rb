# frozen_string_literal: true

module RecordingStudioApi
  module Serializers
    class RecordingSerializer
      class << self
        def call(recording)
          return recording if recording.is_a?(Hash)

          serialize_recording(recording)
        end

        private

        def serialize_recording(recording)
          {
            id: recording.id,
            type: resource_type_for(recording.recordable_type),
            actions: action_names_for(recording.recordable_type),
            root_id: recording.root_recording_id,
            parent_id: recording.parent_recording_id
          }
        end

        def resource_type_for(recordable_type)
          recordable_type.to_s.demodulize.underscore
        end

        def action_names_for(recordable_type)
          return [] unless RecordingStudioApi.respond_to?(:capability_actions_for)

          RecordingStudioApi.capability_actions_for(recordable_type).map(&:name)
        end
      end
    end
  end
end
