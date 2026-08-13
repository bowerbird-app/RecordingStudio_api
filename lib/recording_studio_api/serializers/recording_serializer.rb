# frozen_string_literal: true

module RecordingStudioApi
  module Serializers
    class RecordingSerializer
      class << self
        def call(recording, version: nil, api: :public)
          return recording if recording.is_a?(Hash)

          serialize_recording(recording, version: version, api: api)
        end

        private

        def serialize_recording(recording, version: nil, api: :public)
          {
            id: recording.id,
            type: resource_type_for(recording.recordable_type),
            actions: action_names_for(recording.recordable_type, version: version, api: api),
            root_id: recording.root_recording_id,
            parent_id: recording.parent_recording_id,
            created_at: recording.respond_to?(:created_at) ? recording.created_at : nil,
            updated_at: recording.respond_to?(:updated_at) ? recording.updated_at : nil
          }
        end

        def resource_type_for(recordable_type)
          recordable_type.to_s.demodulize.underscore
        end

        def action_names_for(recordable_type, version: nil, api: :public)
          return [] unless RecordingStudioApi.respond_to?(:capability_actions_for)

          RecordingStudioApi.capability_actions_for(recordable_type, version: version, api: api).map(&:name)
        end
      end
    end
  end
end
