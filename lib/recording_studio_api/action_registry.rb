# frozen_string_literal: true

require_relative "action_registration"
require_relative "errors"

module RecordingStudioApi
  class ActionRegistry
    def initialize
      @registrations = {}
    end

    def register(name, capability:, http_verb: :post, handler:, serializer: nil, scope: :member, openapi: nil, input_contract: nil)
      registration = ActionRegistration.new(
        name: name,
        capability: capability,
        http_verb: http_verb,
        handler: handler,
        serializer: serializer,
        scope: scope,
        openapi: openapi,
        input_contract: input_contract
      )
      registration.validate!

      key = registration.name
      raise ConfigurationError, "API action #{key} is already registered" if @registrations.key?(key)

      @registrations[key] = registration
    end

    def fetch(name)
      @registrations.fetch(name.to_s)
    end

    def [](name)
      @registrations[name.to_s]
    end

    def available_for(recordable_type, scope: nil)
      @registrations.values.select do |registration|
        registration.applicable_to?(recordable_type) && (scope.nil? || registration.scope == scope.to_sym)
      end
    end

    def to_h
      @registrations.transform_values(&:as_json)
    end

    def validate!
      @registrations.each_value(&:validate!)
    end
  end
end
