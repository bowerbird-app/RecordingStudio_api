# frozen_string_literal: true

module RecordingStudioApi
  module Serializers
    class ResourceRecordingSerializer
      class << self
        def call(recording)
          base_payload = RecordingSerializer.call(recording)
          return base_payload if recording.is_a?(Hash)

          registration = RecordingStudioApi.recordable_registration_for(recording.recordable_type)
          return base_payload unless registration&.serializer

          base_payload.merge(attributes: registration.serializer.call(recording.recordable))
        end
      end
    end
  end
end