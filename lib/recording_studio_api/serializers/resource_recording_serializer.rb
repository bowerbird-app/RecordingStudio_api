# frozen_string_literal: true

module RecordingStudioApi
  module Serializers
    class ResourceRecordingSerializer
      BASE_KEYS = %w[id type parent_id root_id created_at updated_at].freeze
      RESERVED_KEYS = (BASE_KEYS + ["_meta", "actions"]).freeze

      class << self
        def call(recording, version: nil, api: :public, context: nil, expand_relationships: true)
          return recording if recording.is_a?(Hash)

          registration = RecordingStudioApi.recordable_registration_for(recording.recordable_type, api: api)
          serializer_context = SerializerContext.build(
            recording: recording, context: context, api_version: version, api_key: api, registration: registration
          )
          payload = RecordingSerializer.call(recording, version: version, api: api)
          merge_serializer_output!(payload, serialized_attributes(registration, serializer_context), registration)
          merge_fields!(payload, resolved_fields(registration, serializer_context), registration)
          merge_relationships!(payload, recording, registration, serializer_context, version, api) if expand_relationships
          payload
        end

        private

        def serialized_attributes(registration, context)
          serializer = registration.serializer if registration&.respond_to?(:serializer)
          return {} unless serializer.respond_to?(:call)

          value = call_with_context(serializer, context.recordable, context)
          raise ConfigurationError, "Serializer for #{registration.recordable_type} must return a hash" unless value.is_a?(Hash)

          stringify_keys(value)
        end

        def resolved_fields(registration, context)
          return {} unless registration

          registration.fields.each_with_object({}) do |(name, definition), values|
            next unless context.include?(name, definition)

            field_context = context.with(field: definition)
            authorize_field!(name, definition, field_context)
            values[name.to_s] = json_safe!(definition.resolver.call(field_context), name)
          end
        end

        def authorize_field!(name, definition, context)
          return unless definition.authorize
          raise AuthorizationError, "Cannot authorize field #{name} without an access grant" unless context.access_grant

          allowed = definition.authorize.call(context)
          raise AuthorizationError, "Not authorized to read field #{name}" unless allowed == true
        rescue AuthorizationError
          raise
        rescue StandardError
          raise AuthorizationError, "Not authorized to read field #{name}"
        end

        def merge_relationships!(payload, recording, registration, context, version, api)
          return unless registration

          registration.relationships.each do |name, definition|
            next unless context.include?(name, definition)

            value = context.relationship_value(recording, name, definition)
            payload[name.to_s] = serialize_relationship(value, definition, context.with(relationship: definition), version, api)
            meta = context.relationship_metadata(recording, name)
            add_relationship_meta!(payload, name, meta) unless meta.nil?
          end
        end

        def serialize_relationship(value, definition, context, version, api)
          many = definition.many
          return [] if many && value.nil?
          return nil if value.nil?

          values = many ? Array(value) : [value]
          serialized = values.map { |entry| serialize_relationship_entry(entry, definition, context, version, api) }
          many ? serialized : serialized.first
        end

        def serialize_relationship_entry(value, definition, context, version, api)
          raise ConfigurationError, "Relationship value must be a recording" unless recording?(value)

          relationship_context = context.with(recordable: value.recordable, target_recording: value)
          payload = RecordingSerializer.call(value, version: version, api: api)
          output = call_with_context(definition.serializer, value.recordable, relationship_context)
          raise ConfigurationError, "Relationship serializer must return a hash" unless output.is_a?(Hash)

          merge_relationship_serializer_output!(payload, stringify_keys(output), definition)
          payload
        end

        def merge_serializer_output!(payload, values, registration)
          return if values.empty?

          declared = Array(registration&.output_keys).map(&:to_s)
          relationships = registration ? registration.relationships.keys.map(&:to_s) : []
          fields = registration ? registration.fields.keys.map(&:to_s) : []
          invalid = values.keys & (RESERVED_KEYS + fields + relationships)
          raise ConfigurationError, "Serializer emitted reserved keys: #{invalid.join(', ')}" if invalid.any?
          undeclared = values.keys - declared
          raise ConfigurationError, "Serializer emitted undeclared keys: #{undeclared.join(', ')}" if undeclared.any?
          collisions = values.keys & payload.keys.map(&:to_s)
          raise ConfigurationError, "Serializer collided with response keys: #{collisions.join(', ')}" if collisions.any?

          values.each { |key, value| payload[key.to_sym] = json_safe!(value, key) }
        end

        def merge_fields!(payload, values, registration)
          return if values.empty?

          relationship_names = registration.relationships.keys.map(&:to_s)
          invalid = values.keys & (RESERVED_KEYS + Array(registration.output_keys).map(&:to_s) + relationship_names)
          raise ConfigurationError, "Fields emitted reserved keys: #{invalid.join(', ')}" if invalid.any?
          collisions = values.keys & payload.keys.map(&:to_s)
          raise ConfigurationError, "Fields collided with response keys: #{collisions.join(', ')}" if collisions.any?

          values.each { |key, value| payload[key.to_sym] = value }
        end

        def merge_relationship_serializer_output!(payload, values, definition)
          invalid = values.keys & RESERVED_KEYS
          raise ConfigurationError, "Relationship serializer emitted reserved keys: #{invalid.join(', ')}" if invalid.any?
          undeclared = values.keys - definition.output_keys
          raise ConfigurationError, "Relationship serializer emitted undeclared keys: #{undeclared.join(', ')}" if undeclared.any?
          collisions = values.keys & payload.keys.map(&:to_s)
          raise ConfigurationError, "Relationship serializer collided with response keys: #{collisions.join(', ')}" if collisions.any?

          values.each { |key, value| payload[key.to_sym] = json_safe!(value, key) }
        end

        def add_relationship_meta!(payload, name, meta)
          payload[:_meta] ||= {}
          raise ConfigurationError, "Relationship metadata for #{name} must be JSON-safe" unless json_safe?(meta)

          payload[:_meta][name.to_s] = meta
        end

        def call_with_context(callable, value, context)
          parameters = callable.respond_to?(:parameters) ? callable.parameters : callable.method(:call).parameters
          accepts_context = parameters.any? do |kind, name|
            [:key, :keyreq, :keyrest].include?(kind) && (name == :context || kind == :keyrest)
          end
          accepts_context ? callable.call(value, context: context) : callable.call(value)
        end

        def json_safe!(value, name)
          raise ConfigurationError, "#{name} must be JSON-safe" unless json_safe?(value)

          value
        end

        def json_safe?(value)
          case value
          when nil, String, Numeric, TrueClass, FalseClass
            true
          when Array
            value.all? { |entry| json_safe?(entry) }
          when Hash
            value.all? { |key, entry| (key.is_a?(String) || key.is_a?(Symbol)) && json_safe?(entry) }
          else
            false
          end
        end

        def recording?(value)
          value.respond_to?(:recordable_type) && value.respond_to?(:recordable) && value.respond_to?(:id)
        end

        def stringify_keys(value)
          value.each_with_object({}) { |(key, entry), output| output[key.to_s] = entry }
        end
      end
    end
  end
end
