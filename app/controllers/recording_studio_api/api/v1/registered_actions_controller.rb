# frozen_string_literal: true

module RecordingStudioApi
  module Api
    module V1
      class RegisteredActionsController < RecordingStudioApi::ApiController
        RESERVED_PARAM_KEYS = %w[
          action
          controller
          format
          registered_action
          standalone_path
          api_key
          api_version
        ].freeze

        def invoke
          match = resolve_match!
          action = match.action
          raise UnsupportedActionError, "#{action.name} must be called with #{action.http_verb.to_s.upcase}" unless request.request_method_symbol == action.http_verb

          result = action.handler.call(action_context(action, match.captures))
          render json: serialize_result(action, result)
        end

        private

        def resolve_match!
          match = RecordingStudioApi.registered_action_request_match(request)
          raise RecordingStudioApi::NotFoundError, "Unknown API action" if match.nil?

          match
        end

        def action_context(action, captures)
          RecordingStudioApi::RegisteredActionContext.new(
            api_client: current_api_client,
            credential: current_api_credential,
            access_recording: current_access_recording,
            access_grant: current_access_grant,
            root_recording: current_root_recording,
            params: action_params(action, captures)
          )
        end

        def action_params(action, captures)
          raw_params = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : {}
          filtered_params = raw_params.except(*RESERVED_PARAM_KEYS)
          normalized_params = filtered_params.respond_to?(:deep_symbolize_keys) ? filtered_params.deep_symbolize_keys : {}
          merged_params = normalized_params.merge(captures)

          return merged_params if action.input_contract.nil?

          contract_result = action.input_contract.call(merged_params)
          return contract_result.value if contract_result.success?

          raise InvalidActionInputError.new(
            "Invalid input for action #{action.name}",
            details: contract_result.errors
          )
        end

        def serialize_result(action, result)
          serializer = action.serializer
          return result if serializer.nil?

          serializer.call(result)
        end
      end
    end
  end
end
