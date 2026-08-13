# frozen_string_literal: true

require_relative "recordable_registration"
require_relative "errors"

module RecordingStudioApi
  class RecordableRegistry
    def initialize
      @registrations = {}
    end

    def register(recordable_type, serializer: nil, output_keys: nil, fields: nil, openapi: nil,
                 sortable_attributes: nil, writable_attributes: nil, immutable_fields: nil,
                 relationships: nil, immutable_relationships: nil, operations: nil, capability_actions: nil)
      incoming = RecordableRegistration.new(
        recordable_type: recordable_type, serializer: serializer, output_keys: output_keys, fields: fields,
        openapi: openapi, sortable_attributes: sortable_attributes, writable_attributes: writable_attributes,
        immutable_fields: immutable_fields, relationships: relationships,
        immutable_relationships: immutable_relationships, operations: operations,
        capability_actions: capability_actions
      )
      key = incoming.recordable_type
      @registrations[key] = merge_registrations(@registrations[key], incoming)
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
      return incoming unless existing

      RecordableRegistration.new(
        recordable_type: incoming.recordable_type,
        serializer: merge_value("serializer", existing.serializer, incoming.serializer),
        output_keys: existing.output_keys | incoming.output_keys,
        fields: merge_definitions("field", existing.fields, incoming.fields),
        openapi: deep_merge_hashes(existing.openapi, incoming.openapi),
        sortable_attributes: existing.sortable_attributes | incoming.sortable_attributes,
        writable_attributes: existing.writable_attributes | incoming.writable_attributes,
        immutable_fields: existing.immutable_fields | incoming.immutable_fields,
        relationships: merge_definitions("relationship", existing.relationships, incoming.relationships),
        immutable_relationships: existing.immutable_relationships | incoming.immutable_relationships,
        operations: merge_explicit_set("operations", existing.operations, incoming.operations,
                                       existing.operations_supplied?, incoming.operations_supplied?),
        capability_actions: merge_explicit_set("capability actions", existing.capability_actions, incoming.capability_actions,
                                               existing.capability_actions_supplied?, incoming.capability_actions_supplied?),
        operations_supplied: existing.operations_supplied? || incoming.operations_supplied?,
        capability_actions_supplied: existing.capability_actions_supplied? || incoming.capability_actions_supplied?
      )
    end

    def merge_definitions(kind, existing, incoming)
      existing.merge(incoming) do |name, established, replacement|
        raise ConfigurationError, "#{kind.capitalize} #{name} cannot be redefined incompatibly" unless established == replacement

        established
      end
    end

    def merge_value(name, established, replacement)
      return replacement unless established
      return established unless replacement
      return established if established == replacement

      raise ConfigurationError, "#{name.capitalize} cannot be redefined incompatibly"
    end

    def merge_explicit_set(name, established, replacement, established_supplied, replacement_supplied)
      return replacement if replacement_supplied && !established_supplied
      return established if established_supplied && !replacement_supplied
      return established unless established_supplied || replacement_supplied
      return established if established == replacement

      raise ConfigurationError, "#{name.capitalize} cannot be redefined incompatibly"
    end

    def deep_merge_hashes(base, overlay)
      base.merge(overlay) do |_key, base_value, overlay_value|
        base_value.is_a?(Hash) && overlay_value.is_a?(Hash) ? deep_merge_hashes(base_value, overlay_value) : overlay_value
      end
    end
  end
end
