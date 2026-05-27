# frozen_string_literal: true

require_relative "action_input_contract"

module RecordingStudioApi
  class ActionRegistration
    ALLOWED_HTTP_VERBS = %i[get post patch put delete].freeze
    ALLOWED_SCOPES = %i[collection resource member].freeze

    attr_reader :name, :capability, :http_verb, :handler, :serializer, :scope, :openapi, :input_contract

    def initialize(name:, capability:, http_verb:, handler:, serializer: nil, scope: :member, openapi: nil, input_contract: nil)
      @name = name.to_s
      @capability = capability&.to_sym
      @http_verb = http_verb.to_sym
      @handler = handler
      @serializer = serializer
      @scope = scope.to_sym
      @openapi = normalize_openapi(openapi)
      @input_contract = normalize_input_contract(input_contract)
    end

    def validate!
      raise ConfigurationError, "API action name is required" if name.blank?
      raise ConfigurationError, "Capability is required for #{name}" if capability.blank? && scope == :member
      raise ConfigurationError, "Handler is required for #{name}" unless handler.respond_to?(:call)
      raise ConfigurationError, "Unsupported HTTP verb #{http_verb} for #{name}" unless ALLOWED_HTTP_VERBS.include?(http_verb)
      raise ConfigurationError, "Unsupported scope #{scope} for #{name}" unless ALLOWED_SCOPES.include?(scope)
      raise ConfigurationError, "Serializer must respond to call for #{name}" if serializer && !serializer.respond_to?(:call)
      raise ConfigurationError, "OpenAPI metadata must be a hash for #{name}" unless openapi.is_a?(Hash)
      raise ConfigurationError, "Input contract must be a RecordingStudioApi::ActionInputContract for #{name}" if input_contract && !input_contract.is_a?(ActionInputContract)
    end

    def applicable_to?(recordable_type)
      capability_enabled_for?(recordable_type)
    end

    def as_json(*)
      {
        name: name,
        action: capability,
        http_verb: http_verb,
        scope: scope,
        openapi: openapi,
        input_contract: input_contract&.as_json
      }
    end

    private

    def capability_enabled_for?(recordable_type)
      return recordable_type.present? if capability.blank?
      return false if recordable_type.blank?
      return false unless defined?(RecordingStudio) && RecordingStudio.respond_to?(:capability_enabled?)

      RecordingStudio.capability_enabled?(capability, for: recordable_type)
    end

    def normalize_openapi(value)
      return {} if value.nil?
      return value.deep_symbolize_keys if value.respond_to?(:deep_symbolize_keys)

      value
    end

    def normalize_input_contract(value)
      return if value.nil?
      return value if value.is_a?(ActionInputContract)

      ActionInputContract.new(value)
    end
  end
end
