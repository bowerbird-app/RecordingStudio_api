# frozen_string_literal: true

module RecordingStudioApi
  class RecordableRegistration
    attr_reader :recordable_type, :serializer, :openapi, :sortable_attributes, :writable_attributes

    def initialize(recordable_type:, serializer: nil, openapi: nil, sortable_attributes: nil, writable_attributes: nil)
      @recordable_type = recordable_type.to_s
      @serializer = serializer
      @openapi = normalize_openapi(openapi)
      @sortable_attributes = normalize_sortable_attributes(sortable_attributes)
      @writable_attributes = normalize_attributes(writable_attributes)
    end

    def validate!
      raise ConfigurationError, "Recordable type is required" if recordable_type.blank?
      raise ConfigurationError, "Serializer must respond to call for #{recordable_type}" if serializer && !serializer.respond_to?(:call)
      raise ConfigurationError, "OpenAPI metadata must be a hash for #{recordable_type}" unless openapi.is_a?(Hash)
      unless sortable_attributes.is_a?(Array)
        raise ConfigurationError, "Sortable attributes must be an array for #{recordable_type}"
      end

      invalid_sortable_attributes = sortable_attributes.reject { |attribute| attribute.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/) }
      if invalid_sortable_attributes.any?
        raise ConfigurationError, "Sortable attributes are invalid for #{recordable_type}: #{invalid_sortable_attributes.join(', ')}"
      end

      invalid_writable_attributes = writable_attributes.reject { |attribute| attribute.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/) }
      if invalid_writable_attributes.any?
        raise ConfigurationError, "Writable attributes are invalid for #{recordable_type}: #{invalid_writable_attributes.join(', ')}"
      end
    end

    def as_json(*)
      {
        recordable_type: recordable_type,
        serializer: serializer.present?,
        openapi: openapi,
        sortable_attributes: sortable_attributes,
        writable_attributes: writable_attributes
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
  end
end