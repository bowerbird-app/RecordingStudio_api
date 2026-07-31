# frozen_string_literal: true

module RecordingStudioApi
  module Serializers
    class ResourceRecordingSerializer
      class << self
        def call(recording, version: nil, api: :public)
          base_payload = RecordingSerializer.call(recording, version: version, api: api)
          return base_payload if recording.is_a?(Hash)

          registration = RecordingStudioApi.recordable_registration_for(recording.recordable_type, api: api)
          attributes = custom_attributes_for(registration, recording.recordable)

          return base_payload if attributes.empty?

          base_payload.merge(attributes: attributes)
        end

        private

        def custom_attributes_for(registration, recordable)
          return {} unless registration&.serializer

          normalize_hash(registration.serializer.call(recordable))
        end

        def normalize_hash(value)
          return {} unless value.respond_to?(:to_h)

          stringify_keys(value.to_h)
        end

        def stringify_keys(value)
          case value
          when Hash
            value.each_with_object({}) do |(key, child_value), output|
              output[key.to_s] = stringify_keys(child_value)
            end
          when Array
            value.map { |child_value| stringify_keys(child_value) }
          else
            value
          end
        end
      end
    end
  end
end