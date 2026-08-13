# frozen_string_literal: true

module RecordingStudioApi
  class RecordableRegistration
    DEFAULT_OPERATIONS = %i[index show create update destroy].freeze
    RELATIONSHIP_SOURCES = %i[children custom].freeze
    INCLUDE_POLICIES = [true, :request, false].freeze
    ENDPOINTS = %i[index show create update destroy].freeze
    DIRECT_CHILD_ORDER_ATTRIBUTES = %w[created_at id].freeze
    FIELD_NAME_PATTERN = /\A[a-zA-Z_][a-zA-Z0-9_]*\z/
    RESERVED_RESPONSE_KEYS = %w[id type parent_id root_id created_at updated_at actions _meta].freeze

    class FieldDefinition
      attr_reader :resolver, :include, :authorize, :openapi

      def initialize(resolver:, include:, authorize:, openapi:)
        @resolver = resolver
        @include = include
        @authorize = authorize
        @openapi = openapi
        freeze
      end

      def ==(other)
        other.is_a?(self.class) && to_h == other.to_h
      end
      alias eql? ==

      def to_h
        { resolver: resolver, include: include, authorize: authorize, openapi: openapi }.freeze
      end

      def [](key)
        public_send(key)
      end
    end

    class RelationshipDefinition
      attr_reader :source, :child_type, :many, :include, :resolver, :serializer, :output_keys,
                  :limit, :order, :endpoints, :authorize, :description, :openapi

      def initialize(source:, child_type:, many:, include:, resolver:, serializer:, output_keys:, limit:, order:, endpoints:, authorize:, description:, openapi:)
        @source = source
        @child_type = child_type
        @many = many
        @include = include
        @resolver = resolver
        @serializer = serializer
        @output_keys = output_keys
        @limit = limit
        @order = order
        @endpoints = endpoints
        @authorize = authorize
        @description = description
        @openapi = openapi
        freeze
      end

      def ==(other)
        other.is_a?(self.class) && to_h == other.to_h
      end
      alias eql? ==

      def to_h
        {
          source: source, child_type: child_type, many: many, include: include, resolver: resolver,
          serializer: serializer, output_keys: output_keys, limit: limit, order: order,
          endpoints: endpoints, authorize: authorize, description: description, openapi: openapi
        }.freeze
      end

      def [](key)
        public_send(key)
      end
    end

    attr_reader :recordable_type, :serializer, :output_keys, :fields, :openapi, :sortable_attributes,
                :writable_attributes, :immutable_fields, :relationships, :immutable_relationships,
                :operations, :capability_actions

    def initialize(recordable_type:, serializer: nil, output_keys: nil, fields: nil, openapi: nil,
                   sortable_attributes: nil, writable_attributes: nil, immutable_fields: nil,
                   relationships: nil, immutable_relationships: nil, operations: nil, capability_actions: nil,
                   operations_supplied: nil, capability_actions_supplied: nil)
      @recordable_type = recordable_type.to_s
      @serializer = serializer
      @output_keys = normalize_names(output_keys, "Output keys")
      @fields = normalize_fields(fields)
      @openapi = normalize_openapi(openapi)
      @sortable_attributes = normalize_names(sortable_attributes, "Sortable attributes").sort.freeze
      @writable_attributes = normalize_names(writable_attributes, "Writable attributes").sort.freeze
      @immutable_fields = normalize_names(immutable_fields, "Immutable fields").sort.freeze
      @relationships = normalize_relationships(relationships)
      @immutable_relationships = normalize_names(immutable_relationships, "Immutable relationships").sort.freeze
      @operations_supplied = operations_supplied.nil? ? !operations.nil? : operations_supplied
      @capability_actions_supplied = capability_actions_supplied.nil? ? !capability_actions.nil? : capability_actions_supplied
      @operations = normalize_operations(operations)
      @capability_actions = normalize_capability_actions(capability_actions)
      validate!
      freeze
    end

    def validate!
      raise ConfigurationError, "Recordable type is required" if recordable_type.blank?
      raise ConfigurationError, "Serializer must respond to call for #{recordable_type}" if serializer && !serializer.respond_to?(:call)
      if serializer && output_keys.empty?
        raise ConfigurationError, "Output keys are required when serializer is configured for #{recordable_type}"
      end
      if serializer.nil? && output_keys.any?
        raise ConfigurationError, "Serializer is required when output keys are configured for #{recordable_type}"
      end

      validate_reserved_names!(output_keys, "Output keys")
      validate_reserved_names!(fields.keys, "Field names")
      validate_reserved_names!(relationships.keys, "Relationship names")
      collisions = (output_keys & fields.keys) | (output_keys & relationships.keys) | (fields.keys & relationships.keys)
      raise ConfigurationError, "Response keys collide for #{recordable_type}: #{collisions.sort.join(', ')}" if collisions.any?

      invalid_immutable_fields = immutable_fields - writable_attributes
      if invalid_immutable_fields.any?
        raise ConfigurationError, "Immutable fields must be writable attributes for #{recordable_type}: #{invalid_immutable_fields.join(', ')}"
      end

      invalid_immutable_relationships = immutable_relationships - relationships.keys
      if invalid_immutable_relationships.any?
        raise ConfigurationError, "Immutable relationships are not registered for #{recordable_type}: #{invalid_immutable_relationships.join(', ')}"
      end

      invalid_operations = operations - DEFAULT_OPERATIONS
      raise ConfigurationError, "Unsupported API operations for #{recordable_type}: #{invalid_operations.join(', ')}" if invalid_operations.any?

      invalid_actions = capability_actions.reject { |action| action.match?(FIELD_NAME_PATTERN) }
      if invalid_actions.any?
        raise ConfigurationError, "Capability actions are invalid for #{recordable_type}: #{invalid_actions.join(', ')}"
      end

      true
    end

    def supports_operation?(operation)
      operations.include?(operation.to_sym)
    end

    def supports_capability_action?(action)
      capability_actions.include?(action.to_s)
    end

    def operations_supplied?
      @operations_supplied
    end

    def capability_actions_supplied?
      @capability_actions_supplied
    end

    def as_json(*)
      {
        recordable_type: recordable_type, serializer: serializer, output_keys: output_keys,
        fields: fields.transform_values(&:to_h), openapi: openapi, sortable_attributes: sortable_attributes,
        writable_attributes: writable_attributes, immutable_fields: immutable_fields,
        relationships: relationships.transform_values(&:to_h), immutable_relationships: immutable_relationships,
        operations: operations, capability_actions: capability_actions
      }
    end

    private

    def normalize_fields(value)
      return {}.freeze if value.nil?
      raise ConfigurationError, "Fields must be a hash for #{recordable_type}" unless value.is_a?(Hash)

      value.each_with_object({}) do |(name, options), fields|
        field_name = normalize_name(name, "Field name")
        if options.is_a?(FieldDefinition)
          fields[field_name] = options
          next
        end
        raise ConfigurationError, "Field #{field_name} must be a hash for #{recordable_type}" unless options.is_a?(Hash)

        normalized = symbolize_keys(options)
        reject_unknown_options!(normalized, %i[resolver include authorize openapi], "Field #{field_name}")
        resolver = normalized[:resolver]
        raise ConfigurationError, "Field #{field_name} resolver must respond to call for #{recordable_type}" unless resolver.respond_to?(:call)

        include_policy = normalize_include(normalized.fetch(:include, false), "Field #{field_name}")
        authorize = normalized[:authorize]
        raise ConfigurationError, "Field #{field_name} authorize must respond to call for #{recordable_type}" if authorize && !authorize.respond_to?(:call)

        fields[field_name] = FieldDefinition.new(resolver: resolver, include: include_policy, authorize: authorize, openapi: normalize_openapi(normalized[:openapi]))
      end.freeze
    end

    def normalize_relationships(value)
      return {}.freeze if value.nil?
      raise ConfigurationError, "Relationships must be a hash for #{recordable_type}" unless value.is_a?(Hash)

      value.each_with_object({}) do |(name, options), relationships|
        relationship_name = normalize_name(name, "Relationship name")
        if options.is_a?(RelationshipDefinition)
          relationships[relationship_name] = options
          next
        end
        raise ConfigurationError, "Relationship #{relationship_name} must be a hash for #{recordable_type}" unless options.is_a?(Hash)

        normalized = symbolize_keys(options)
        reject_unknown_options!(normalized, %i[source child_type many include resolver serializer output_keys limit order endpoints authorize description openapi], "Relationship #{relationship_name}")
        source = normalized[:source]&.to_s&.to_sym
        unless RELATIONSHIP_SOURCES.include?(source)
          raise ConfigurationError, "Relationship #{relationship_name} source must be one of: #{RELATIONSHIP_SOURCES.join(', ')} for #{recordable_type}"
        end

        many = normalized[:many]
        raise ConfigurationError, "Relationship #{relationship_name} many must be boolean for #{recordable_type}" unless [true, false].include?(many)

        child_type, resolver = normalize_relationship_source!(relationship_name, source, normalized)
        serializer = normalized[:serializer]
        unless serializer.respond_to?(:call)
          raise ConfigurationError, "Relationship #{relationship_name} serializer must respond to call for #{recordable_type}"
        end

        output_keys = normalize_names(normalized[:output_keys], "Relationship #{relationship_name} output keys")
        raise ConfigurationError, "Relationship #{relationship_name} output_keys are required for #{recordable_type}" if output_keys.empty?

        validate_reserved_names!(output_keys, "Relationship #{relationship_name} output keys")
        limit = normalize_limit(relationship_name, many, normalized.key?(:limit), normalized[:limit])
        order = normalize_order(relationship_name, many, normalized.key?(:order), normalized[:order])
        endpoints = normalize_endpoints(relationship_name, source, many, normalized.key?(:endpoints), normalized[:endpoints])
        include_policy = normalize_include(normalized.fetch(:include, false), "Relationship #{relationship_name}")
        authorize = normalized[:authorize]
        raise ConfigurationError, "Relationship #{relationship_name} authorize must respond to call for #{recordable_type}" if authorize && !authorize.respond_to?(:call)
        description = normalize_description(normalized[:description], "Relationship #{relationship_name}")

        relationships[relationship_name] = RelationshipDefinition.new(
          source: source, child_type: child_type, many: many, include: include_policy, resolver: resolver,
          serializer: serializer, output_keys: output_keys, limit: limit, order: order, endpoints: endpoints,
          authorize: authorize, description: description, openapi: normalize_openapi(normalized[:openapi])
        )
      end.freeze
    end

    def normalize_relationship_source!(name, source, options)
      if source == :children
        raise ConfigurationError, "Relationship #{name} requires child_type for #{recordable_type}" if options[:child_type].blank?
        raise ConfigurationError, "Relationship #{name} cannot specify resolver for children source" if options.key?(:resolver)

        child_type = options[:child_type].to_s
        unless child_type.match?(/\A[A-Z][a-zA-Z0-9_:]*\z/)
          raise ConfigurationError, "Relationship #{name} child_type is invalid for #{recordable_type}"
        end

        [child_type.freeze, nil]
      else
        raise ConfigurationError, "Relationship #{name} requires resolver for custom source" unless options[:resolver].respond_to?(:call)
        raise ConfigurationError, "Relationship #{name} cannot specify child_type for custom source" if options.key?(:child_type)

        [nil, options[:resolver]]
      end
    end

    def normalize_limit(name, many, supplied, value)
      if !many && supplied
        raise ConfigurationError, "Relationship #{name} limit is only valid when many is true for #{recordable_type}"
      end
      return nil unless many
      unless value.is_a?(Integer) && value.positive?
        raise ConfigurationError, "Relationship #{name} limit must be a positive integer for #{recordable_type}"
      end

      value
    end

    def normalize_order(name, many, supplied, value)
      if !many && supplied
        raise ConfigurationError, "Relationship #{name} order is only valid when many is true for #{recordable_type}"
      end
      return {}.freeze unless supplied
      raise ConfigurationError, "Relationship #{name} order must be a nonempty hash for #{recordable_type}" unless value.is_a?(Hash) && value.any?

      value.each_with_object({}) do |(attribute, direction), order|
        attribute_name = normalize_name(attribute, "Relationship #{name} order attribute")
        unless DIRECT_CHILD_ORDER_ATTRIBUTES.include?(attribute_name)
          raise ConfigurationError, "Relationship #{name} order attribute is not supported for #{recordable_type}: #{attribute_name}"
        end

        normalized_direction = direction.to_s.to_sym
        unless %i[asc desc].include?(normalized_direction)
          raise ConfigurationError, "Relationship #{name} order direction must be asc or desc for #{recordable_type}"
        end

        order[attribute_name] = normalized_direction
      end.freeze
    end

    def normalize_endpoints(name, source, many, supplied, value)
      endpoints = Array(value).map { |endpoint| endpoint.to_s.to_sym }.uniq.sort
      if supplied && !(source == :children && many)
        raise ConfigurationError, "Relationship #{name} endpoints require a many children relationship for #{recordable_type}"
      end
      return endpoints.freeze if endpoints.empty?

      invalid = endpoints - ENDPOINTS
      raise ConfigurationError, "Relationship #{name} endpoints are invalid for #{recordable_type}: #{invalid.join(', ')}" if invalid.any?

      endpoints.freeze
    end

    def normalize_include(value, label)
      return value if INCLUDE_POLICIES.include?(value)

      raise ConfigurationError, "#{label} include must be true, :request, or false for #{recordable_type}"
    end

    def normalize_description(value, label)
      return nil if value.nil?
      raise ConfigurationError, "#{label} description must be a string for #{recordable_type}" unless value.is_a?(String)

      value.squish.presence
    end

    def normalize_openapi(value)
      return {}.freeze if value.nil?
      raise ConfigurationError, "OpenAPI metadata must be a hash for #{recordable_type}" unless value.is_a?(Hash)

      deep_freeze(symbolize_keys(value))
    end

    def normalize_names(value, label)
      Array(value).map { |name| normalize_name(name, label) }.uniq.freeze
    end

    def normalize_name(value, label)
      name = value.to_s
      raise ConfigurationError, "#{label} is invalid for #{recordable_type}: #{name}" unless name.match?(FIELD_NAME_PATTERN)

      name
    end

    def validate_reserved_names!(names, label)
      reserved = names & RESERVED_RESPONSE_KEYS
      raise ConfigurationError, "#{label} are reserved for #{recordable_type}: #{reserved.join(', ')}" if reserved.any?
    end

    def normalize_operations(value)
      (Array(value).presence || DEFAULT_OPERATIONS).map { |operation| operation.to_s.to_sym }.uniq.sort.freeze
    end

    def normalize_capability_actions(value)
      Array(value).map(&:to_s).uniq.sort.freeze
    end

    def reject_unknown_options!(options, allowed, label)
      unknown = options.keys - allowed
      raise ConfigurationError, "#{label} options are invalid for #{recordable_type}: #{unknown.join(', ')}" if unknown.any?
    end

    def symbolize_keys(value)
      value.each_with_object({}) do |(key, child_value), output|
        output[key.to_sym] = child_value.is_a?(Hash) ? symbolize_keys(child_value) : child_value
      end
    end

    def deep_freeze(value)
      case value
      when Hash then value.each do |key, child|
        deep_freeze(key)
        deep_freeze(child)
      end.freeze
      when Array then value.each { |child| deep_freeze(child) }.freeze
      else value.freeze
      end
    end
  end
end
