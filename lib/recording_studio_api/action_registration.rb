# frozen_string_literal: true

require "date"
require "rubygems/version"

require_relative "action_input_contract"

module RecordingStudioApi
  class ActionRegistration
    ALLOWED_HTTP_VERBS = %i[get post patch put delete].freeze
    ALLOWED_SCOPES = %i[collection resource member].freeze

    attr_reader :name, :capability, :version, :version_notes, :deprecation, :http_verb, :handler, :serializer, :scope, :openapi, :input_contract

    def initialize(name:, capability:, http_verb:, handler:, version: nil, version_notes: nil, deprecation: nil, serializer: nil, scope: :member, openapi: nil, input_contract: nil)
      @name = name.to_s
      @capability = capability&.to_sym
      @version = normalize_version(version)
      @version_notes = normalize_version_notes(version_notes)
      @deprecation = normalize_deprecation(deprecation)
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
      raise ConfigurationError, "version_notes must be a string or array of strings for #{name}" unless version_notes.is_a?(Array)
      raise ConfigurationError, "deprecation must be a hash for #{name}" unless deprecation.is_a?(Hash)
    end

    def applicable_to?(recordable_type)
      capability_enabled_for?(recordable_type)
    end

    def contribution_keys
      keys = [capability, name.to_sym].compact
      keys << :moveable if keys.include?(:movable)
      keys << :movable if keys.include?(:moveable)
      keys.uniq
    end

    def as_json(*)
      {
        name: name,
        action: capability,
        version: version.to_s,
        version_notes: version_notes,
        deprecation: deprecation,
        http_verb: http_verb,
        scope: scope,
        openapi: openapi,
        input_contract: input_contract&.as_json
      }
    end

    private

    def normalize_version(value)
      raw_version = value.nil? ? "1.0" : value.to_s.strip
      raise ConfigurationError, "API action version is required for #{name}" if raw_version.empty?

      Gem::Version.new(raw_version)
    rescue ArgumentError => e
      raise ConfigurationError, "Invalid API action version for #{name}: #{e.message}"
    end

    def normalize_version_notes(value)
      return [] if value.nil?

      notes = value.is_a?(Array) ? value : [value]
      notes.map do |note|
        normalized = note.to_s.strip
        raise ConfigurationError, "version_notes entries must be present for #{name}" if normalized.empty?

        normalized
      end
    end

    def normalize_deprecation(value)
      return {} if value.nil?
      raise ConfigurationError, "deprecation must be a hash for #{name}" unless value.respond_to?(:to_h)

      normalized = value.to_h.deep_symbolize_keys
      deprecated = normalized[:deprecated]
      removal_date = normalized[:removal_date]
      reason = normalized[:reason]

      raise ConfigurationError, "deprecation[:deprecated] must be true or false for #{name}" unless deprecated.nil? || deprecated == true || deprecated == false

      if removal_date.present?
        parsed_date = Date.iso8601(removal_date.to_s)
        normalized[:removal_date] = parsed_date.iso8601
      end

      if reason.present?
        normalized[:reason] = reason.to_s.strip
        raise ConfigurationError, "deprecation[:reason] must be present for #{name}" if normalized[:reason].empty?
      elsif normalized.key?(:reason)
        raise ConfigurationError, "deprecation[:reason] must be present for #{name}"
      end

      normalized.slice(:deprecated, :removal_date, :reason)
    rescue Date::Error, ArgumentError => e
      raise ConfigurationError, "Invalid deprecation metadata for #{name}: #{e.message}"
    end

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
