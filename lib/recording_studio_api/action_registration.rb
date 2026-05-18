# frozen_string_literal: true

module RecordingStudioApi
  class ActionRegistration
    ALLOWED_HTTP_VERBS = %i[get post patch put delete].freeze
    ALLOWED_SCOPES = %i[member].freeze

    attr_reader :name, :capability, :http_verb, :handler, :serializer, :scope

    def initialize(name:, capability:, http_verb:, handler:, serializer: nil, scope: :member)
      @name = name.to_s
      @capability = capability.to_sym
      @http_verb = http_verb.to_sym
      @handler = handler
      @serializer = serializer
      @scope = scope.to_sym
    end

    def validate!
      raise ConfigurationError, "API action name is required" if name.blank?
      raise ConfigurationError, "Capability is required for #{name}" if capability.blank?
      raise ConfigurationError, "Handler is required for #{name}" unless handler.respond_to?(:call)
      raise ConfigurationError, "Unsupported HTTP verb #{http_verb} for #{name}" unless ALLOWED_HTTP_VERBS.include?(http_verb)
      raise ConfigurationError, "Unsupported scope #{scope} for #{name}" unless ALLOWED_SCOPES.include?(scope)
      raise ConfigurationError, "Serializer must respond to call for #{name}" if serializer && !serializer.respond_to?(:call)
    end

    def applicable_to?(recordable_type)
      capability_enabled_for?(recordable_type)
    end

    def as_json(*)
      {
        name: name,
        capability: capability,
        http_verb: http_verb,
        scope: scope
      }
    end

    private

    def capability_enabled_for?(recordable_type)
      return false if recordable_type.blank?
      return false unless defined?(RecordingStudio) && RecordingStudio.respond_to?(:capability_enabled?)

      RecordingStudio.capability_enabled?(capability, for: recordable_type)
    end
  end
end
