# frozen_string_literal: true

module RecordingStudioApi
  class Lookup
    Result = Data.define(:handler, :input_contract, :output_schema, :sensitive, :apis)

    def self.call(api: :public, recordable_type: nil, operation: nil, action: nil, endpoint: nil, version: nil)
      new(
        api: api,
        recordable_type: recordable_type,
        operation: operation,
        action: action,
        endpoint: endpoint,
        version: version
      ).call
    end

    def initialize(api:, recordable_type:, operation:, action:, endpoint:, version:)
      @api = api
      @recordable_type = recordable_type
      @operation = operation
      @action = action
      @endpoint = endpoint
      @version = version
    end

    def call
      kinds = [type_operation?, action_target?, endpoint_target?].count(true)
      raise ArgumentError, "lookup requires exactly one of operation, action, or endpoint" unless kinds == 1
      raise ArgumentError, "recordable_type is required when looking up an operation" if type_operation? && @recordable_type.blank?

      if type_operation?
        lookup_type_operation
      elsif action_target?
        lookup_capability_action
      else
        lookup_endpoint
      end
    end

    private

    def type_operation?
      !@operation.nil?
    end

    def action_target?
      !@action.nil?
    end

    def endpoint_target?
      !@endpoint.nil?
    end

    def lookup_type_operation
      operation = @operation.to_sym
      registration = RecordingStudioApi.recordable_registration_for(@recordable_type, api: @api)
      return unless registration&.supports_operation?(operation)

      handler = RecordingStudioApi.resource_handler(@recordable_type, operation, api: @api)
      handler ||= RecordingStudioApi.resource_action(operation, version: @version, api: @api)&.handler
      return unless handler

      Result.new(
        handler: handler,
        input_contract: dup_payload(type_operation_input_contract(registration, operation)),
        output_schema: dup_payload(Services::DocumentationCatalog.recording_schema(@recordable_type, api: @api)),
        sensitive: registration.sensitive_operation?(operation, api: @api),
        apis: apis_for { |api| type_operation_on?(api, operation) }
      )
    end

    def lookup_capability_action
      action = RecordingStudioApi.capability_action(@action, version: @version, api: @api)
      return unless action

      handler = RecordingStudioApi.resource_handler(@recordable_type, action.name, api: @api) if @recordable_type.present?
      handler ||= action.handler

      Result.new(
        handler: handler,
        input_contract: contract_fields(action.input_contract),
        output_schema: dup_payload(action_output_schema(action)),
        sensitive: action.sensitive,
        apis: apis_for { |api| RecordingStudioApi.capability_action(@action, version: @version, api: api) }
      )
    end

    def lookup_endpoint
      endpoint = RecordingStudioApi.registered_endpoint(@endpoint, api: @api)
      return unless endpoint

      Result.new(
        handler: endpoint.handler,
        input_contract: contract_fields(endpoint.input_contract),
        output_schema: dup_payload(endpoint_output_schema(endpoint)),
        sensitive: endpoint.sensitive,
        apis: apis_for { |api| RecordingStudioApi.registered_endpoint(@endpoint, api: api) }
      )
    end

    def type_operation_on?(api, operation)
      RecordingStudioApi.recordable_registration_for(@recordable_type, api: api)&.supports_operation?(operation)
    end

    def apis_for(&)
      RecordingStudioApi.configuration.each_api.filter_map do |definition|
        name = definition.name.to_sym
        name if yield(name)
      end
    end

    def type_operation_input_contract(registration, operation)
      return {} unless %i[create update].include?(operation)

      names = Array(registration.writable_attributes).map(&:to_s)
      names -= Array(registration.immutable_fields).map(&:to_s) if operation == :update
      names.to_h { |name| [name.to_sym, { type: :string, required: false, allow_blank: true }] }
    end

    def contract_fields(contract)
      return {} unless contract

      payload = contract.as_json
      fields = payload.is_a?(Hash) ? payload[:fields] || payload["fields"] : nil
      dup_payload(fields)
    end

    def dup_payload(value)
      copied = value.nil? ? {} : value.deep_dup
      copied.freeze if copied.respond_to?(:freeze)
      copied
    end

    def action_output_schema(action)
      documented_schema(action.openapi) || { type: "object" }
    end

    def endpoint_output_schema(endpoint)
      documented_schema(endpoint.openapi) || { type: "object" }
    end

    def documented_schema(openapi)
      return unless openapi.is_a?(Hash)

      responses = openapi[:responses]
      return unless responses.is_a?(Hash)

      response = responses["200"] || responses[:"200"] || responses[:ok]
      return unless response.is_a?(Hash)

      content = response[:content]
      return unless content.is_a?(Hash)

      json = content[:"application/json"] || content["application/json"]
      json.is_a?(Hash) ? json[:schema] || json["schema"] : nil
    end
  end

  def self.lookup(...) = Lookup.call(...)
end
