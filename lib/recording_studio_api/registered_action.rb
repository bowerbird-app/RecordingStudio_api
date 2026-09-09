# frozen_string_literal: true

require_relative "action_input_contract"

module RecordingStudioApi
  class RegisteredAction
    ALLOWED_HTTP_VERBS = %i[get post patch put delete].freeze
    DEFAULT_OPENAPI_TAG = "Actions"
    PATH_TOKEN = /\A:[a-z][a-z0-9_]*\z/
    STATIC_SEGMENT = /\A[a-z0-9](?:[a-z0-9_-]*[a-z0-9])?\z/i

    Match = Data.define(:action, :captures)

    attr_reader :name, :http_verb, :path, :handler, :serializer, :openapi, :input_contract

    def initialize(name:, http_verb:, path:, handler:, serializer: nil, openapi: nil, input_contract: nil)
      @name = name.to_s
      @http_verb = http_verb.to_sym
      @path = normalize_path(path)
      @handler = handler
      @serializer = serializer
      @openapi = normalize_openapi(openapi)
      @input_contract = normalize_input_contract(input_contract)
    end

    def validate!
      raise ConfigurationError, "API action name is required" if name.blank?
      raise ConfigurationError, "Handler is required for #{name}" unless handler.respond_to?(:call)
      raise ConfigurationError, "Unsupported HTTP verb #{http_verb} for #{name}" unless ALLOWED_HTTP_VERBS.include?(http_verb)
      raise ConfigurationError, "Serializer must respond to call for #{name}" if serializer && !serializer.respond_to?(:call)
      raise ConfigurationError, "OpenAPI metadata must be a hash for #{name}" unless openapi.is_a?(Hash)
      raise ConfigurationError, "Input contract must be a RecordingStudioApi::ActionInputContract for #{name}" if input_contract && !input_contract.is_a?(ActionInputContract)
    end

    def path_segments
      @path_segments ||= path.split("/")
    end

    def match(path)
      incoming = normalize_request_path(path)
      incoming_segments = incoming.split("/")
      return if incoming_segments.length != path_segments.length

      captures = {}
      matched = path_segments.each_with_index.all? do |template, index|
        value = incoming_segments[index]
        if template.start_with?(":")
          captures[template.delete_prefix(":").to_sym] = value
          true
        else
          template == value
        end
      end
      return unless matched

      Match.new(action: self, captures: captures)
    end

    def openapi_path_parameters
      path_segments.filter_map do |segment|
        next unless segment.start_with?(":")

        {
          name: segment.delete_prefix(":"),
          in: "path",
          required: true,
          schema: { type: "string" }
        }
      end
    end

    def openapi_tags
      Array(openapi.fetch(:tags, [DEFAULT_OPENAPI_TAG]))
    end

    def as_json(*)
      {
        name: name,
        http_verb: http_verb,
        path: path,
        openapi: openapi,
        input_contract: input_contract&.as_json
      }
    end

    private

    def normalize_path(value)
      raw = value.to_s.strip.sub(%r{\A/}, "").sub(%r{/\z}, "")
      raise ConfigurationError, "API action path is required for #{name}" if raw.blank?
      raise ConfigurationError, "API action path must be relative for #{name}" if raw.include?("://") || raw.start_with?("\\")
      raise ConfigurationError, "API action path must not contain .. for #{name}" if raw.split("/").include?("..")

      segments = raw.split("/")
      raise ConfigurationError, "API action path must not contain empty segments for #{name}" if segments.any?(&:blank?)

      segments.each do |segment|
        next if segment.match?(PATH_TOKEN) || segment.match?(STATIC_SEGMENT)

        raise ConfigurationError, "Invalid API action path segment #{segment.inspect} for #{name}"
      end

      segments.join("/")
    end

    def normalize_request_path(value)
      value.to_s.sub(%r{\A/}, "").sub(%r{/\z}, "").sub(/\.json\z/, "")
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
