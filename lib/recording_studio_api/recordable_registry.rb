# frozen_string_literal: true

require_relative "recordable_registration"
require_relative "errors"

module RecordingStudioApi
  class RecordableRegistry
    def initialize
      @registrations = {}
    end

    def register(recordable_type, output_keys: nil, fields: nil, openapi: nil, sortable_attributes: nil,
                 writable_attributes: nil, immutable_fields: nil, relationships: nil, immutable_relationships: nil,
                 operations: nil, capability_actions: nil)
      existing = @registrations[recordable_type.to_s]
      resolved_writable_attributes = existing ? existing.writable_attributes | Array(writable_attributes) : writable_attributes
      registration = RecordableRegistration.new(
        recordable_type: recordable_type,
        output_keys: output_keys,
        fields: fields,
        openapi: openapi,
        sortable_attributes: sortable_attributes,
        writable_attributes: resolved_writable_attributes,
        immutable_fields: immutable_fields,
        relationships: relationships,
        immutable_relationships: immutable_relationships,
        operations: operations,
        capability_actions: capability_actions
      )
      registration.validate!

      key = registration.recordable_type
      @registrations[key] = merge_registrations(existing, registration)
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
        output_keys: existing.output_keys | incoming.output_keys,
        fields: merge_fields(existing.fields, incoming.fields),
        openapi: deep_merge_hashes(existing.openapi, incoming.openapi),
        sortable_attributes: existing.sortable_attributes | incoming.sortable_attributes,
        writable_attributes: (existing.writable_attributes | incoming.writable_attributes).sort,
        immutable_fields: (existing.immutable_fields | incoming.immutable_fields).sort,
        relationships: merge_relationships(existing.relationships, incoming.relationships),
        immutable_relationships: (existing.immutable_relationships | incoming.immutable_relationships).sort,
        operations: existing.operations & incoming.operations,
        capability_actions: (existing.capability_actions | incoming.capability_actions).sort
      )
      merged.validate!
      merged
    end

    def normalize_hash(value)
      return {} unless value.respond_to?(:to_h)

      symbolize_keys(value.to_h)
    end

    def merge_fields(base, overlay)
      return base if overlay == {}
      return overlay if base == {}
      return overlay if base.respond_to?(:call) || overlay.respond_to?(:call)

      base.merge(overlay)
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

    def merge_relationships(base, overlay)
      base.merge(overlay) do |_name, existing, incoming|
        unless existing[:source] == incoming[:source]
          raise ConfigurationError, "Relationship source cannot change once registered"
        end

        {
          source: existing[:source],
          types: (Array(existing[:types]) | Array(incoming[:types])).sort,
          include: existing[:include] == true || incoming[:include] == true ? true : :request,
          read: existing[:read] && incoming[:read],
          write: existing[:write] && incoming[:write],
          resolver: incoming[:resolver] || existing[:resolver],
          method: incoming[:method] || existing[:method],
          serializer: incoming[:serializer] || existing[:serializer],
          output_keys: Array(existing[:output_keys]) | Array(incoming[:output_keys]),
          fields: merge_fields(existing[:fields] || {}, incoming[:fields] || {}),
          openapi: deep_merge_hashes(existing[:openapi] || {}, incoming[:openapi] || {})
        }
      end
    end
  end
end