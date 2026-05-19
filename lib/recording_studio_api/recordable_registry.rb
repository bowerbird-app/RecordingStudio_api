# frozen_string_literal: true

require_relative "recordable_registration"
require_relative "errors"

module RecordingStudioApi
  class RecordableRegistry
    def initialize
      @registrations = {}
    end

    def register(recordable_type, serializer: nil, openapi: nil)
      registration = RecordableRegistration.new(
        recordable_type: recordable_type,
        serializer: serializer,
        openapi: openapi
      )
      registration.validate!

      key = registration.recordable_type
      @registrations[key] = registration
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
  end
end