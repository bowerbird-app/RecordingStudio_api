# frozen_string_literal: true

module RecordingStudioApi
  class RecordableRegistration
    attr_reader :recordable_type, :serializer, :openapi

    def initialize(recordable_type:, serializer: nil, openapi: nil)
      @recordable_type = recordable_type.to_s
      @serializer = serializer
      @openapi = normalize_openapi(openapi)
    end

    def validate!
      raise ConfigurationError, "Recordable type is required" if recordable_type.blank?
      raise ConfigurationError, "Serializer must respond to call for #{recordable_type}" if serializer && !serializer.respond_to?(:call)
      raise ConfigurationError, "OpenAPI metadata must be a hash for #{recordable_type}" unless openapi.is_a?(Hash)
    end

    def as_json(*)
      {
        recordable_type: recordable_type,
        serializer: serializer.present?,
        openapi: openapi
      }
    end

    private

    def normalize_openapi(value)
      return {} if value.nil?
      return value.deep_symbolize_keys if value.respond_to?(:deep_symbolize_keys)

      value
    end
  end
end