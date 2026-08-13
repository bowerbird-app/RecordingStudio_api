# frozen_string_literal: true

module RecordingStudioApi
  class RecordableRegistration
    DEFAULT_OPERATIONS = %i[index show create update destroy].freeze
    RELATIONSHIP_SOURCES = %i[children custom].freeze
    RELATIONSHIP_INCLUDE_POLICIES = [true, :request].freeze
    FIELD_NAME_PATTERN = /\A[a-zA-Z_][a-zA-Z0-9_]*\z/

    attr_reader :recordable_type, :output_keys, :fields, :openapi, :sortable_attributes,
                :writable_attributes, :immutable_fields, :relationships, :immutable_relationships,
                :operations, :capability_actions

    def initialize(recordable_type:, output_keys: nil, fields: nil, openapi: nil, sortable_attributes: nil,
                   writable_attributes: nil, immutable_fields: nil, relationships: nil, immutable_relationships: nil,
                   operations: nil, capability_actions: nil)
      @recordable_type = recordable_type.to_s
      @fields = normalize_fields(fields)
      @output_keys = normalize_output_keys(output_keys || (fields.is_a?(Hash) ? fields.keys : nil))
      @openapi = normalize_openapi(openapi)
      @sortable_attributes = normalize_sortable_attributes(sortable_attributes)
      @writable_attributes = normalize_attributes(writable_attributes)
      @immutable_fields = normalize_attributes(immutable_fields)
      @relationships = normalize_relationships(relationships)
      @immutable_relationships = normalize_attributes(immutable_relationships)
      @operations = normalize_operations(operations)
      @capability_actions = normalize_capability_actions(capability_actions)
    end

    def validate!
      raise ConfigurationError, "Recordable type is required" if recordable_type.blank?
      raise ConfigurationError, "OpenAPI metadata must be a hash for #{recordable_type}" unless openapi.is_a?(Hash)
      unless sortable_attributes.is_a?(Array)
        raise ConfigurationError, "Sortable attributes must be an array for #{recordable_type}"
      end

      invalid_output_keys = output_keys.reject { |key| key.match?(FIELD_NAME_PATTERN) }
      if invalid_output_keys.any?
        raise ConfigurationError, "Output keys are invalid for #{recordable_type}: #{invalid_output_keys.join(', ')}"
      end

      if fields.respond_to?(:call) && output_keys.empty?
        raise ConfigurationError, "Output keys are required when fields is callable for #{recordable_type}"
      end

      invalid_field_names = field_names.reject { |key| key.match?(FIELD_NAME_PATTERN) }
      if invalid_field_names.any?
        raise ConfigurationError, "Field names are invalid for #{recordable_type}: #{invalid_field_names.join(', ')}"
      end

      invalid_sortable_attributes = sortable_attributes.reject { |attribute| attribute.match?(FIELD_NAME_PATTERN) }
      if invalid_sortable_attributes.any?
        raise ConfigurationError, "Sortable attributes are invalid for #{recordable_type}: #{invalid_sortable_attributes.join(', ')}"
      end

      invalid_writable_attributes = writable_attributes.reject { |attribute| attribute.match?(FIELD_NAME_PATTERN) }
      if invalid_writable_attributes.any?
        raise ConfigurationError, "Writable attributes are invalid for #{recordable_type}: #{invalid_writable_attributes.join(', ')}"
      end

      invalid_immutable_fields = immutable_fields - writable_attributes
      if invalid_immutable_fields.any?
        raise ConfigurationError, "Immutable fields must be writable attributes for #{recordable_type}: #{invalid_immutable_fields.join(', ')}"
      end

      invalid_immutable_relationships = immutable_relationships - relationships.keys
      if invalid_immutable_relationships.any?
        raise ConfigurationError, "Immutable relationships are not registered for #{recordable_type}: #{invalid_immutable_relationships.join(', ')}"
      end

      invalid_operations = operations - DEFAULT_OPERATIONS
      if invalid_operations.any?
        raise ConfigurationError, "Unsupported API operations for #{recordable_type}: #{invalid_operations.join(', ')}"
      end

      invalid_capability_actions = capability_actions.reject { |action| action.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/) }
      if invalid_capability_actions.any?
        raise ConfigurationError, "Capability actions are invalid for #{recordable_type}: #{invalid_capability_actions.join(', ')}"
      end
    end

    def supports_operation?(operation)
      operations.include?(operation.to_sym)
    end

    def supports_capability_action?(action)
      capability_actions.include?(action.to_s)
    end

    def as_json(*)
      {
        recordable_type: recordable_type,
        output_keys: output_keys,
        fields: fields_as_json,
        openapi: openapi,
        sortable_attributes: sortable_attributes,
        writable_attributes: writable_attributes,
        immutable_fields: immutable_fields,
        relationships: relationships,
        immutable_relationships: immutable_relationships,
        operations: operations,
        capability_actions: capability_actions
      }
    end

    private

    def normalize_openapi(value)
      return {} if value.nil?
      return value.deep_symbolize_keys if value.respond_to?(:deep_symbolize_keys)

      value
    end

    def normalize_sortable_attributes(value)
      normalize_attributes(value)
    end

    def normalize_attributes(value)
      Array(value).map(&:to_s).uniq.sort
    end

    def normalize_output_keys(value)
      Array(value).map(&:to_s).uniq
    end

    def normalize_fields(value)
      return {} if value.nil?
      return value if value.respond_to?(:call)

      unless value.is_a?(Hash)
        raise ConfigurationError, "Fields must be a hash or callable for #{recordable_type}"
      end

      value.each_with_object({}) do |(name, definition), output|
        output[name.to_s] = normalize_field_definition(definition)
      end.freeze
    end

    def normalize_field_definition(definition)
      return definition unless definition.is_a?(Hash)

      definition.deep_symbolize_keys.freeze
    end

    def normalize_operations(value)
      configured_operations = Array(value).presence || DEFAULT_OPERATIONS
      configured_operations.map(&:to_sym).uniq.sort
    end

    def normalize_capability_actions(value)
      Array(value).map(&:to_s).uniq.sort
    end

    def normalize_relationships(value)
      return {} if value.nil?
      raise ConfigurationError, "Relationships must be a hash for #{recordable_type}" unless value.is_a?(Hash)

      value.each_with_object({}) do |(name, options), output|
        relationship_name = name.to_s
        unless relationship_name.match?(FIELD_NAME_PATTERN)
          raise ConfigurationError, "Relationship name is invalid for #{recordable_type}: #{relationship_name}"
        end

        normalized_options = options
        unless normalized_options.is_a?(Hash)
          raise ConfigurationError, "Relationship #{relationship_name} must be a hash for #{recordable_type}"
        end

        normalized_options = normalized_options.deep_symbolize_keys
        source = normalized_options.fetch(:source, nil)&.to_sym
        unless RELATIONSHIP_SOURCES.include?(source)
          raise ConfigurationError,
                "Relationship #{relationship_name} source must be one of: #{RELATIONSHIP_SOURCES.join(', ')} for #{recordable_type}"
        end

        include_policy = normalize_relationship_include(normalized_options.fetch(:include, :request), relationship_name)
        types = Array(normalized_options.fetch(:types, [])).map(&:to_s).uniq.sort
        invalid_types = types.reject { |type| type.match?(/\A[A-Z][a-zA-Z0-9_:]*\z/) }
        if invalid_types.any?
          raise ConfigurationError, "Relationship types are invalid for #{recordable_type}: #{invalid_types.join(', ')}"
        end

        unknown_options = normalized_options.keys - %i[
          source types include read write resolver custom method serializer output_keys fields openapi
        ]
        if unknown_options.any?
          raise ConfigurationError, "Relationship options are invalid for #{recordable_type}: #{unknown_options.join(', ')}"
        end

        relationship_fields = normalize_relationship_fields(normalized_options[:fields])
        relationship_output_keys = normalize_output_keys(
          normalized_options[:output_keys] || (relationship_fields.is_a?(Hash) ? relationship_fields.keys : nil)
        )
        invalid_output_keys = relationship_output_keys.reject { |key| key.match?(FIELD_NAME_PATTERN) }
        if invalid_output_keys.any?
          raise ConfigurationError,
                "Relationship output keys are invalid for #{recordable_type}: #{invalid_output_keys.join(', ')}"
        end
        if relationship_fields.is_a?(Hash)
          invalid_field_names = relationship_fields.keys.reject { |key| key.match?(FIELD_NAME_PATTERN) }
          if invalid_field_names.any?
            raise ConfigurationError,
                  "Relationship field names are invalid for #{recordable_type}: #{invalid_field_names.join(', ')}"
          end
        end
        resolver = normalized_options[:resolver] || normalized_options[:custom]
        if resolver && !resolver.respond_to?(:call)
          raise ConfigurationError, "Relationship #{relationship_name} resolver must respond to call for #{recordable_type}"
        end
        if normalized_options[:serializer] && !normalized_options[:serializer].respond_to?(:call)
          raise ConfigurationError, "Relationship #{relationship_name} serializer must respond to call for #{recordable_type}"
        end
        method_name = (normalized_options[:method] || relationship_name).to_s
        unless method_name.match?(FIELD_NAME_PATTERN)
          raise ConfigurationError, "Relationship #{relationship_name} method is invalid for #{recordable_type}"
        end
        if source == :custom && !normalized_options[:serializer].respond_to?(:call) && relationship_output_keys.empty?
          raise ConfigurationError,
                "Custom relationship #{relationship_name} requires output_keys and fields or a serializer for #{recordable_type}"
        end

        output[relationship_name] = {
          source: source,
          types: types,
          include: include_policy,
          read: normalized_options.fetch(:read, true) == true,
          write: normalized_options.fetch(:write, true) == true,
          resolver: resolver,
          method: method_name.to_sym,
          serializer: normalized_options[:serializer],
          output_keys: relationship_output_keys,
          fields: relationship_fields,
          openapi: normalized_options[:openapi]
        }.freeze
      end.freeze
    end

    def normalize_relationship_include(value, relationship_name)
      return value if RELATIONSHIP_INCLUDE_POLICIES.include?(value)
      return :request if value.to_s == "request"

      raise ConfigurationError,
            "Relationship #{relationship_name} include must be true or :request for #{recordable_type}"
    end

    def normalize_relationship_fields(value)
      return {} if value.nil?
      return value if value.respond_to?(:call)

      raise ConfigurationError, "Relationship fields must be a hash or callable for #{recordable_type}" unless value.is_a?(Hash)

      value.each_with_object({}) do |(name, definition), output|
        output[name.to_s] = normalize_field_definition(definition)
      end.freeze
    end

    def field_names
      fields.is_a?(Hash) ? fields.keys : []
    end

    def fields_as_json
      return :callable if fields.respond_to?(:call)

      fields
    end
  end
end