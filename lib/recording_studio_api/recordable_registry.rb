# frozen_string_literal: true

require_relative "recordable_registration"
require_relative "errors"

module RecordingStudioApi
  class RecordableRegistry
    def initialize
      @registrations = {}
    end

    def register(recordable_type, serializer: nil, openapi: nil, sortable_attributes: nil, writable_attributes: nil)
      registration = RecordableRegistration.new(
        recordable_type: recordable_type,
        serializer: serializer,
        openapi: openapi,
        sortable_attributes: sortable_attributes,
        writable_attributes: writable_attributes
      )
      registration.validate!

      key = registration.recordable_type
      @registrations[key] = merge_registrations(@registrations[key], registration)
    end

    def fetch(recordable_type)
      @registrations.fetch(recordable_type.to_s)
    end

    def [](recordable_type)
      @registrations[recordable_type.to_s]
    end

    def to_h
      @registrations.transform_values(&:as_json)
    end

    def validate!
      @registrations.each_value(&:validate!)
    end

    private

    def merge_registrations(existing, incoming)
      return incoming if existing.nil?

      merged = RecordableRegistration.new(
        recordable_type: incoming.recordable_type,
        serializer: compose_serializers(existing.serializer, incoming.serializer),
        openapi: deep_merge_hashes(existing.openapi, incoming.openapi),
        sortable_attributes: existing.sortable_attributes | incoming.sortable_attributes,
        writable_attributes: (existing.writable_attributes | incoming.writable_attributes).sort
      )
      merged.validate!
      merged
    end

    def compose_serializers(base_serializer, overlay_serializer)
      return overlay_serializer if base_serializer.nil?
      return base_serializer if overlay_serializer.nil?

      lambda do |recordable|
        base_payload = normalize_hash(base_serializer.call(recordable))
        overlay_payload = normalize_hash(overlay_serializer.call(recordable))
        deep_merge_hashes(base_payload, overlay_payload)
      end
    end

    def normalize_hash(value)
      return {} unless value.respond_to?(:to_h)

      symbolize_keys(value.to_h)
    end

    def symbolize_keys(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, child_value), output|
          normalized_key = key.respond_to?(:to_sym) ? key.to_sym : key
          output[normalized_key] = symbolize_keys(child_value)
        end
      when Array
        value.map { |child_value| symbolize_keys(child_value) }
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