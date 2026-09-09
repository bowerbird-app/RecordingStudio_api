# frozen_string_literal: true

require_relative "registered_endpoint"
require_relative "errors"

module RecordingStudioApi
  class RegisteredEndpointRegistry
    def initialize
      @registrations = {}
    end

    def register(name, http_verb:, path:, handler:, serializer: nil, openapi: nil, input_contract: nil)
      registration = RegisteredEndpoint.new(
        name: name,
        http_verb: http_verb,
        path: path,
        handler: handler,
        serializer: serializer,
        openapi: openapi,
        input_contract: input_contract
      )
      registration.validate!

      key = registration.name
      raise ConfigurationError, "API endpoint #{key} is already registered" if @registrations.key?(key)
      raise ConfigurationError, "API endpoint path #{registration.http_verb.to_s.upcase} #{registration.path} is already registered" if path_taken?(registration)

      @registrations[key] = registration
    end

    def fetch(name)
      @registrations.fetch(name.to_s)
    end

    def [](name)
      @registrations[name.to_s]
    end

    def all
      @registrations.values
    end

    def match_path(path)
      @registrations.each_value do |registration|
        matched = registration.match(path)
        return matched if matched
      end

      nil
    end

    def match(path:, http_verb:)
      verb = http_verb.to_sym
      @registrations.each_value do |registration|
        next unless registration.http_verb == verb

        matched = registration.match(path)
        return matched if matched
      end

      nil
    end

    def to_h
      @registrations.transform_values(&:as_json)
    end

    def validate!
      @registrations.each_value(&:validate!)
    end

    private

    def path_taken?(registration)
      @registrations.each_value.any? do |existing|
        existing.http_verb == registration.http_verb && existing.path == registration.path
      end
    end
  end
end
