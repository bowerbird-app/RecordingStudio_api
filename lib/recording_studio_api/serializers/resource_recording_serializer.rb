# frozen_string_literal: true

module RecordingStudioApi
  module Serializers
    class ResourceRecordingSerializer
      EXCLUDED_DEFAULT_ATTRIBUTES = %w[id created_at updated_at].freeze

      class << self
        def call(recording, version: nil)
          base_payload = RecordingSerializer.call(recording, version: version)
          return base_payload if recording.is_a?(Hash)

          registration = RecordingStudioApi.recordable_registration_for(recording.recordable_type)
          attributes = deep_merge_hashes(
            default_attributes_for(recording.recordable),
            custom_attributes_for(registration, recording.recordable)
          )

          return base_payload if attributes.empty?

          base_payload.merge(attributes: attributes)
        end

        private

        def custom_attributes_for(registration, recordable)
          return {} unless registration&.serializer

          normalize_hash(registration.serializer.call(recordable))
        end

        def default_attributes_for(recordable)
          return {} unless recordable.respond_to?(:attributes)

          normalize_hash(recordable.attributes).each_with_object({}) do |(key, value), output|
            next if EXCLUDED_DEFAULT_ATTRIBUTES.include?(key.to_s)

            output[key] = value
          end
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

        def deep_merge_hashes(base, overlay)
          base_hash = normalize_hash(base)
          overlay_hash = normalize_hash(overlay)

          base_hash.merge(overlay_hash) do |_key, base_value, overlay_value|
            if base_value.is_a?(Hash) && overlay_value.is_a?(Hash)
              deep_merge_hashes(base_value, overlay_value)
            else
              overlay_value
            end
          end
        end
      end
    end
  end
end