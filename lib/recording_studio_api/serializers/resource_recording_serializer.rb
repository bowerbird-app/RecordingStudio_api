# frozen_string_literal: true

module RecordingStudioApi
  module Serializers
    class ResourceRecordingSerializer
      class << self
        def call(recording, version: nil, api: :public, context: nil)
          base_payload = RecordingSerializer.call(recording, version: version, api: api)
          return base_payload if recording.is_a?(Hash)

          registration = RecordingStudioApi.recordable_registration_for(recording.recordable_type, api: api)
          payload = base_payload.merge(fields_for(registration, recording.recordable, context))
          payload.merge!(relationships_for(recording, registration, context: context, version: version, api: api))
          payload
        end

        private

        def fields_for(registration, recordable, context)
          return {} unless registration

          resolved_fields = resolve_fields(registration.fields, recordable, context)
          registration.output_keys.each_with_object({}) do |key, output|
            next if reserved_keys.include?(key)
            next unless resolved_fields.key?(key)

            output[key.to_sym] = resolved_fields.fetch(key)
          end
        end

        def resolve_fields(fields, recordable, context)
          if fields.respond_to?(:call)
            normalize_hash(call_callable(fields, recordable, context))
          else
            fields.each_with_object({}) do |(name, definition), output|
              output[name.to_s] = resolve_field(recordable, name, definition, context)
            end
          end
        end

        def resolve_field(recordable, name, definition, context)
          return call_callable(definition, recordable, context) if definition.respond_to?(:call)
          return read_field(recordable, name, definition) unless definition.is_a?(Hash)

          resolver = definition[:resolver] || definition[:value]
          return call_callable(resolver, recordable, context) if resolver.respond_to?(:call)
          return resolver unless resolver.nil?

          read_field(recordable, name, definition[:source] || definition[:method] || name)
        end

        def read_field(recordable, name, source)
          return recordable.public_send(source) if source.respond_to?(:to_sym) && recordable.respond_to?(source)
          return recordable[source] if recordable.respond_to?(:[]) && recordable.respond_to?(:key?) && recordable.key?(source)
          return recordable[source.to_s] if recordable.respond_to?(:[]) && recordable.respond_to?(:key?) && recordable.key?(source.to_s)

          recordable.public_send(name) if recordable.respond_to?(name)
        end

        def relationships_for(recording, registration, context:, version:, api:)
          return {} unless registration && context

          registration.relationships.each_with_object({}) do |(name, definition), output|
            next unless definition[:read]
            next unless context.include?(name, definition)

            value = context.relationship_value(recording, name, definition)
            output[name.to_sym] = serialize_relationship_value(value, definition, context, version, api)
          end
        end

        def serialize_relationship_value(value, definition, context, version, api)
          return value.map { |entry| serialize_relationship_value(entry, definition, context, version, api) } if collection?(value)
          return if value.nil?

          return call(value, version: version, api: api, context: context.nested) if recording?(value)

          serializer = definition[:serializer]
          return call_callable(serializer, value, context) if serializer.respond_to?(:call)

          project_relationship_value(value, definition, context)
        end

        def collection?(value)
          value.is_a?(Array) || (value.respond_to?(:to_ary) && !value.is_a?(Hash)) ||
            (value.respond_to?(:to_a) && !value.is_a?(Hash) && !value.is_a?(String) && !recording?(value))
        end

        def recording?(value)
          value.respond_to?(:recordable_type) && value.respond_to?(:recordable) && value.respond_to?(:id)
        end

        def call_callable(callable, value, context)
          callable.call(value, context: context)
        rescue ArgumentError
          callable.call(value)
        end

        def project_relationship_value(value, definition, context)
          fields = definition[:fields]
          return {} unless fields

          resolved_fields = resolve_fields(fields, value, context)
          Array(definition[:output_keys]).each_with_object({}) do |key, output|
            next unless resolved_fields.key?(key)

            output[key.to_sym] = resolved_fields.fetch(key)
          end
        end

        def reserved_keys
          %w[id type actions root_id parent_id created_at updated_at]
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