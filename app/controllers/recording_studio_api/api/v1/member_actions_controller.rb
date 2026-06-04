# frozen_string_literal: true

module RecordingStudioApi
  module Api
    module V1
      class MemberActionsController < RecordingStudioApi::ApiController
        RESERVED_ACTION_PARAM_KEYS = %w[
          action
          action_name
          controller
          format
          id
          resource
        ].freeze

        def create
          action = resolve_action!
          raise UnsupportedActionError, "#{action.name} must be called with #{action.http_verb.to_s.upcase}" unless request.request_method_symbol == action.http_verb

          result = action.handler.call(action_context(action))
          render json: { data: serialize_result(action, result) }
        end

        private

        def action_context(action)
          RecordingStudioApi::ActionContext.new(
            recording: resource_recording,
            api_client: current_api_client,
            credential: current_api_credential,
            access_recording: current_access_recording,
            access_grant: current_access_grant,
            root_recording: current_root_recording,
            params: action_params(action)
          )
        end

        def action_params(action)
          raw_params = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : {}
          filtered_params = raw_params.except(*RESERVED_ACTION_PARAM_KEYS)
          normalized_params = filtered_params.respond_to?(:deep_symbolize_keys) ? filtered_params.deep_symbolize_keys : {}

          return normalized_params if action.input_contract.nil?

          contract_result = action.input_contract.call(normalized_params)
          return contract_result.value if contract_result.success?

          raise InvalidActionInputError.new(
            "Invalid input for action #{action.name}",
            details: contract_result.errors
          )
        end

        def resolve_action!
          action = RecordingStudioApi.capability_action(params[:action_name], version: current_api_version)
          raise UnsupportedActionError, "Unknown API action #{params[:action_name]}" if action.nil?
          raise UnsupportedActionError, "#{action.name} is not enabled for #{resource_recording.recordable_type}" unless action.applicable_to?(resource_recording.recordable_type)

          action
        end

        def resource_recording
          @resource_recording ||= begin
            recordable_type = RecordingStudioApi.recordable_type_for_resource(params[:resource])
            raise RecordingStudioApi::NotFoundError, "Unknown API resource #{params[:resource]}" if recordable_type.blank?

            recording = scoped_recordings.find_by(id: params[:id])
            raise RecordingStudioApi::NotFoundError, "Resource was not found in this API scope" if recording.nil?
            raise RecordingStudioApi::NotFoundError, "Resource type does not match #{recordable_type}" unless recording.recordable_type == recordable_type

            recording
          end
        end

        def scoped_recordings
          @scoped_recordings ||= current_access_grant.accessible_recordings
        end

        def serialize_result(action, result)
          serializer = action.serializer || RecordingStudioApi::Serializers::ResourceRecordingSerializer
          return serializer.call(result, version: current_api_version) if versioned_recording_serializer?(serializer)

          serializer.call(result)
        end

        def versioned_recording_serializer?(serializer)
          [
            RecordingStudioApi::Serializers::RecordingSerializer,
            RecordingStudioApi::Serializers::ResourceRecordingSerializer
          ].include?(serializer)
        end
      end
    end
  end
end
