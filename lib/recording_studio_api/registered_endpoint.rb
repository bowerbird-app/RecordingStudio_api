# frozen_string_literal: true

require_relative "action_input_contract"
require_relative "handler_scope"
require_relative "ui_widget_id"

module RecordingStudioApi
  class RegisteredEndpoint
    ALLOWED_HTTP_VERBS = %i[get post patch put delete].freeze
    DEFAULT_OPENAPI_TAG = "Endpoints"
    PATH_TOKEN = /\A:[a-z][a-z0-9_]*\z/
    STATIC_SEGMENT = /\A[a-z0-9](?:[a-z0-9_-]*[a-z0-9])?\z/i

    Match = Data.define(:endpoint, :captures)

    RECORDING_ID_TOKENS = %w[:id :recording_id].freeze

    attr_reader :name, :http_verb, :path, :handler, :serializer, :openapi, :input_contract, :ui, :recordable_type, :include_trashed, :owns_scoping, :required_role, :scopes_recording, :trashed_semantics

    def initialize(name:, http_verb:, path:, handler:, serializer: nil, openapi: nil, input_contract: nil, ui: nil, recordable_type: nil, include_trashed: false, owns_scoping: false, required_role: nil, **options)
      @name = name.to_s
      @http_verb = http_verb.to_sym
      @path = normalize_path(path)
      @handler = handler
      @serializer = serializer
      @openapi = normalize_openapi(openapi)
      @input_contract = normalize_input_contract(input_contract)
      @ui = UiWidgetId.normalize(ui, name: name)
      raw_recordable_type = recordable_type.to_s.strip
      @recordable_type = raw_recordable_type.empty? ? nil : raw_recordable_type
      @include_trashed = HandlerScope.flag(include_trashed, name: :include_trashed)
      @owns_scoping = HandlerScope.flag(owns_scoping, name: :owns_scoping)
      @required_role = normalize_required_role(required_role)
      scope_id = options.delete(:scope_id)
      @trashed_semantics = HandlerScope.trashed_semantics(options.delete(:trashed_semantics), name: @name)
      raise ArgumentError, "unknown keywords: #{options.keys.join(', ')}" if options.any?

      @scope_id = scope_id.nil? ? nil : HandlerScope.flag(scope_id, name: :scope_id)
      @scopes_recording = false
    end

    def owns_scoping?
      owns_scoping
    end

    def scopes_recording?
      scopes_recording
    end

    def authorization_role
      required_role || (http_verb == :get ? :view : :edit)
    end

    def recording_id_from(captures)
      recording_id = captures[:recording_id]
      return recording_id if recording_id.present?

      captures[:id]
    end

    def validate!
      raise ConfigurationError, "API endpoint name is required" if name.blank?
      raise ConfigurationError, "Handler is required for #{name}" unless handler.respond_to?(:call)
      raise ConfigurationError, "Unsupported HTTP verb #{http_verb} for #{name}" unless ALLOWED_HTTP_VERBS.include?(http_verb)
      raise ConfigurationError, "Serializer must respond to call for #{name}" if serializer && !serializer.respond_to?(:call)
      raise ConfigurationError, "OpenAPI metadata must be a hash for #{name}" unless openapi.is_a?(Hash)
      raise ConfigurationError, "Input contract must be a RecordingStudioApi::ActionInputContract for #{name}" if input_contract && !input_contract.is_a?(ActionInputContract)
      raise ConfigurationError, "required_role must be one of: #{valid_access_roles.join(', ')} for #{name}" if required_role && !valid_access_roles.include?(required_role)

      validate_handler_scope!
    end

    def path_segments
      @path_segments ||= path.split("/")
    end

    def specificity
      path_segments.map { |segment| segment.start_with?(":") ? 0 : 1 }
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

      Match.new(endpoint: self, captures: captures)
    end

    def openapi_path_parameters
      path_segments.filter_map do |segment|
        next unless segment.start_with?(":")

        name = segment.delete_prefix(":")
        {
          name: name,
          in: "path",
          required: true,
          schema: { type: "string" }
        }.merge(path_parameter_documentation(name))
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
        input_contract: input_contract&.as_json,
        ui: ui
      }
    end

    private

    def validate_handler_scope!
      resolve_recording_scope!
      HandlerScope.assert_trashed_semantics!(
        name: name,
        trashed_semantics: trashed_semantics,
        http_verb: http_verb,
        required_role: authorization_role,
        owns_scoping: owns_scoping
      )
      HandlerScope.assert_include_trashed!(name: name, http_verb: http_verb, action_name: trashed_action_name, trashed_semantics: trashed_semantics) if include_trashed
      HandlerScope.assert_read_opt_out!(name: name, http_verb: http_verb, required_role: authorization_role) if owns_scoping
    end

    def resolve_recording_scope!
      captures = path_segments & RECORDING_ID_TOKENS
      raise ConfigurationError, "#{name} cannot capture both :id and :recording_id" if captures.size > 1
      raise ConfigurationError, "scope_id requires a path :id or :recording_id for #{name}" if @scope_id == true && captures.empty?
      raise ConfigurationError, "recordable_type is required when #{name} captures :id or :recording_id, or pass scope_id: false" if @scope_id != false && captures.any? && recordable_type.blank?
      raise ConfigurationError, "required_role is required when #{name} sets scope_id: false on #{http_verb.to_s.upcase}" if @scope_id == false && http_verb != :get && required_role.nil?

      @scopes_recording = @scope_id != false && captures.any? && recordable_type.present?
    end

    def trashed_action_name
      return name if %w[restore destroy].include?(name)

      nil
    end

    def normalize_required_role(value)
      return if value.nil?

      value.to_s.strip.to_sym
    end

    def valid_access_roles
      RecordingStudio::AccessRoles::ORDER.keys.map(&:to_sym)
    end

    def normalize_path(value)
      raw = value.to_s.strip.sub(%r{\A/}, "").sub(%r{/\z}, "")
      raise ConfigurationError, "API endpoint path is required for #{name}" if raw.blank?
      raise ConfigurationError, "API endpoint path must be relative for #{name}" if raw.include?("://") || raw.start_with?("\\")
      raise ConfigurationError, "API endpoint path must not contain .. for #{name}" if raw.split("/").include?("..")

      segments = raw.split("/")
      raise ConfigurationError, "API endpoint path must not contain empty segments for #{name}" if segments.any?(&:blank?)

      segments.each do |segment|
        next if segment.match?(PATH_TOKEN) || segment.match?(STATIC_SEGMENT)

        raise ConfigurationError, "Invalid API endpoint path segment #{segment.inspect} for #{name}"
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

    def path_parameter_documentation(name)
      entry = Array(openapi[:parameters]).find { |parameter| documented_path_parameter?(parameter, name) }
      return {} unless entry

      symbolized_parameter(entry).except(:name, :in, :required)
    end

    def documented_path_parameter?(parameter, name)
      keys = symbolized_parameter(parameter)
      keys[:name].to_s == name && keys[:in].to_s == "path"
    end

    def symbolized_parameter(parameter)
      return parameter.symbolize_keys if parameter.respond_to?(:symbolize_keys)

      parameter
    end

    def normalize_input_contract(value)
      return if value.nil?
      return value if value.is_a?(ActionInputContract)

      ActionInputContract.new(value)
    end
  end
end
