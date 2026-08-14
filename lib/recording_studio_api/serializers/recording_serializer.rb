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
            id: recording.id.to_s,
            type: recording.recordable_type.to_s,
            parent_id: recording.parent_recording_id&.to_s,
            root_id: recording.root_recording_id&.to_s,
            created_at: iso8601(recording, :created_at),
            updated_at: iso8601(recording, :updated_at)
          }
        end

        def iso8601(recording, name)
          value = recording.public_send(name) if recording.respond_to?(name)
          value&.iso8601
        end
      end
    end
  end
end
