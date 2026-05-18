# frozen_string_literal: true

module RecordingStudioApi
  module Serializers
    class RecordingSerializer
      IDENTIFIER_ATTRIBUTES = %i[name title label slug email identifier].freeze

      class << self
        def call(recording)
          return recording if recording.is_a?(Hash)

          serialize_recording(recording)
        end

        private

        def serialize_recording(recording)
          {
            id: recording.id,
            recordable_id: recording.recordable_id,
            recordable_type: recording.recordable_type,
            label: label_for(recording.recordable),
            capabilities: capabilities_for(recording.recordable_type),
            root_recording_id: recording.root_recording_id,
            parent_recording_id: recording.parent_recording_id
          }
        end

        def label_for(recordable)
          return "Unknown recordable" if recordable.nil?

          IDENTIFIER_ATTRIBUTES.each do |attribute|
            next unless recordable.respond_to?(attribute)

            value = recordable.public_send(attribute)
            return value if value.present?
          end

          "##{recordable.id}"
        end

        def capabilities_for(recordable_type)
          return [] unless defined?(RecordingStudio) && RecordingStudio.respond_to?(:capabilities_for)

          RecordingStudio.capabilities_for(recordable_type)
        end
      end
    end
  end
end
