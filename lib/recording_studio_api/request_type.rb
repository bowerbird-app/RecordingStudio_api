# frozen_string_literal: true

module RecordingStudioApi
  module RequestType
    TYPE_KEYS = %w[type parent_type child_type recordable_type].freeze

    module_function

    def validate!(params, api:, expected: nil)
      each_type_value(params, api: api, expected: expected) do |value|
        resolved = RecordingStudioApi.resolve_request_type!(value, api: api)
        next if expected.blank? || resolved == expected.to_s

        raise invalid_type("type does not match this resource")
      end
    end

    def each_type_value(params, api:, expected:)
      hash = params_hash(params)
      TYPE_KEYS.each do |key|
        value = hash[key] || hash[key.to_sym]
        yield value unless value.nil?
      end

      filter_type = filter_type_value(hash, api: api, expected: expected)
      yield filter_type unless filter_type.nil?
    end

    def params_hash(params)
      if params.respond_to?(:to_unsafe_h)
        params.to_unsafe_h
      elsif params.respond_to?(:to_h)
        params.to_h
      else
        {}
      end
    end

    def filter_type_value(hash, api:, expected:)
      raw = hash["filter"] || hash[:filter]
      return if raw.blank?

      filter = params_hash(raw)
      value = filter["type"] || filter[:type]
      return if value.nil?
      return if attribute_filter?(expected, api)

      value
    end

    def attribute_filter?(expected, api)
      return false if expected.blank?

      registration = RecordingStudioApi.recordable_registration_for(expected, api: api)
      Array(registration&.filterable_attributes).include?("type")
    end

    def invalid_type(message)
      InvalidActionInputError.new(
        message,
        details: [
          {
            attribute: :type,
            message: message,
            full_message: message,
            type: :invalid
          }
        ]
      )
    end
  end
end
