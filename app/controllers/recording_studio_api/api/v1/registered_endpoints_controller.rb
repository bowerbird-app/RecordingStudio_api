# frozen_string_literal: true

module RecordingStudioApi
  module Api
    module V1
      class RegisteredEndpointsController < RecordingStudioApi::ApiController
        RESERVED_PARAM_KEYS = %w[
          action
          controller
          format
          registered_endpoint
          standalone_path
          api_key
          api_version
        ].freeze

        def invoke
          match = resolve_match!
          endpoint = match.endpoint
          raise UnsupportedActionError, "#{endpoint.name} must be called with #{endpoint.http_verb.to_s.upcase}" unless request.request_method_symbol == endpoint.http_verb

          result = endpoint.handler.call(endpoint_context(endpoint, match.captures))
          render json: serialize_result(endpoint, result)
        end

        private

        def resolve_match!
          match = RecordingStudioApi.registered_endpoint_request_match(request)
          raise RecordingStudioApi::NotFoundError, "Unknown API endpoint" if match.nil?

          match
        end

        def endpoint_context(endpoint, captures)
          RecordingStudioApi::RegisteredEndpointContext.new(
            api_client: current_api_client,
            credential: current_api_credential,
            access_recording: current_access_recording,
            access_grant: current_access_grant,
            root_recording: current_root_recording,
            params: endpoint_params(endpoint, captures)
          )
        end

        def endpoint_params(endpoint, captures)
          raw_params = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : {}
          filtered_params = raw_params.except(*RESERVED_PARAM_KEYS)
          normalized_params = filtered_params.respond_to?(:deep_symbolize_keys) ? filtered_params.deep_symbolize_keys : {}
          merged_params = normalized_params.merge(captures)

          return merged_params if endpoint.input_contract.nil?

          contract_result = endpoint.input_contract.call(merged_params)
          return contract_result.value if contract_result.success?

          raise InvalidActionInputError.new(
            "Invalid input for endpoint #{endpoint.name}",
            details: contract_result.errors
          )
        end

        def serialize_result(endpoint, result)
          serializer = endpoint.serializer
          return result if serializer.nil?

          serializer.call(result)
        end
      end
    end
  end
end
