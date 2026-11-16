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
        ROUTE_PARAM_KEYS = %w[
          api_key
          api_version
          member_action
        ].freeze

        def create
          action = resolve_action_definition!
          raise UnsupportedActionError, "#{action.name} must be called with #{action.http_verb.to_s.upcase}" unless request.request_method_symbol == action.http_verb

          recordable_type = resolve_recordable_type!
          handler = RecordingStudioApi.resource_handler(recordable_type, action.name, api: current_api_key)
          if handler
            registration = RecordingStudioApi.resource_handler_registration(recordable_type, action.name, api: current_api_key)
            handler_context = member_handler_context(action, recordable_type, registration)
            result = handler.call(handler_context)
            render json: result.fetch(:json), status: result.fetch(:status, :ok)
          else
            context = capability_action_context(action)
            result = action.handler.call(context)
            render json: serialize_result(action, result)
          end
        end

        private

        def resolve_action_definition!
          action = RecordingStudioApi.capability_action(params[:action_name], version: current_api_version, api: current_api_key)
          raise UnsupportedActionError, "Unknown API action #{params[:action_name]}" if action.nil?

          action
        end

        def resolve_recordable_type!
          recordable_type = RecordingStudioApi.recordable_type_for_resource(params[:resource], api: current_api_key)
          raise RecordingStudioApi::NotFoundError, "Unknown API resource #{params[:resource]}" if recordable_type.blank?

          recordable_type
        end

        def member_handler_context(action, recordable_type, registration)
          member_action_context(action, recordable_type, registration: registration) do |recording|
            handler_action_context(action, recordable_type, recording: recording)
          end
        end

        def capability_action_context(action)
          recordable_type = resolve_recordable_type!
          member_action_context(action, recordable_type, registration: nil) do |recording|
            action_context(action, recording: recording, ignored_keys: ROUTE_PARAM_KEYS)
          end
        end

        def member_action_context(action, recordable_type, registration:)
          context = nil
          RecordingStudioApi::HandlerGuard.capability!(
            access_grant: current_access_grant,
            api_client: current_api_client,
            recordable_type: recordable_type,
            action: action,
            id: params[:id],
            registration: registration,
            before_authorize: ->(recording) { assert_member_action_enabled!(action, recording, recordable_type) }
          ) do |recording|
            # owns_scoping reads yield nil before lookup and authorize!.
            assert_member_action_enabled!(action, recording, recordable_type) if recording.nil?
            context = yield(recording)
          end
          context
        end

        def assert_member_action_enabled!(action, recording, recordable_type)
          assert_action_enabled!(action, recording&.recordable_type || recordable_type)
        end

        def handler_action_context(action, recordable_type, recording:)
          RecordingStudioApi::ActionContext.new(
            recording: recording,
            api_client: current_api_client,
            credential: current_api_credential,
            access_recording: current_access_recording,
            access_grant: current_access_grant,
            root_recording: current_root_recording,
            params: action_params(action, ignored_keys: ROUTE_PARAM_KEYS),
            id: params[:id],
            recordable_type: recordable_type
          )
        end

        def action_context(action, recording:, ignored_keys: [])
          RecordingStudioApi::ActionContext.new(
            recording: recording,
            api_client: current_api_client,
            credential: current_api_credential,
            access_recording: current_access_recording,
            access_grant: current_access_grant,
            root_recording: current_root_recording,
            params: action_params(action, ignored_keys: ignored_keys),
            id: params[:id]
          )
        end

        def action_params(action, ignored_keys: [])
          raw_params = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : {}
          filtered_params = raw_params.except(*RESERVED_ACTION_PARAM_KEYS, *ignored_keys)
          normalized_params = filtered_params.respond_to?(:deep_symbolize_keys) ? filtered_params.deep_symbolize_keys : {}

          return normalized_params if action.input_contract.nil?

          contract_result = action.input_contract.call(normalized_params)
          return contract_result.value if contract_result.success?

          raise InvalidActionInputError.new(
            "Invalid input for action #{action.name}",
            details: contract_result.errors
          )
        end

        def assert_action_enabled!(action, recordable_type)
          raise UnsupportedActionError, "#{action.name} is not enabled for #{recordable_type}" unless action.applicable_to?(recordable_type)
          raise UnsupportedActionError, "#{action.name} is not enabled for #{recordable_type}" unless RecordingStudioApi.capability_action_enabled_for?(action, recordable_type, api: current_api_key)
        end

        def scoped_recordings(include_trashed: false)
          @scoped_recordings ||= {}
          @scoped_recordings[include_trashed] ||= current_access_grant.accessible_recordings(include_trashed: include_trashed)
        end

        def serialize_result(action, result)
          serializer = action.serializer || RecordingStudioApi::Serializers::ResourceRecordingSerializer
          if serializer == RecordingStudioApi::Serializers::ResourceRecordingSerializer
            return serializer.call(
              result,
              version: current_api_version,
              api: current_api_key,
              context: relationship_context_for(result)
            )
          end
          return serializer.call(result, version: current_api_version, api: current_api_key) if versioned_recording_serializer?(serializer)

          serializer.call(result)
        end

        def relationship_context_for(result)
          recordings = result.respond_to?(:recordable_type) && result.respond_to?(:recordable) ? [result] : []
          RecordingStudioApi::RelationshipContext.for(
            recordings: recordings,
            include_values: params[:include],
            scoped_recordings: scoped_recordings,
            api_key: current_api_key,
            api_version: current_api_version,
            access_grant: current_access_grant,
            params: params
          )
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
