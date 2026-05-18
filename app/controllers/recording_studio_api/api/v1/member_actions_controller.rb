# frozen_string_literal: true

module RecordingStudioApi
  module Api
    module V1
      class MemberActionsController < RecordingStudioApi::ApiController
        def create
          action = resolve_action!
          raise UnsupportedActionError, "#{action.name} must be called with #{action.http_verb.to_s.upcase}" unless request.request_method_symbol == action.http_verb

          result = action.handler.call(action_context)
          render json: { data: serialize_result(action, result) }
        end

        private

        def action_context
          RecordingStudioApi::ActionContext.new(
            recording: resource_recording,
            api_client: current_api_client,
            credential: current_api_credential,
            access_recording: current_access_recording,
            root_recording: current_root_recording,
            params: member_action_params
          )
        end

        def member_action_params
          params.permit(:destination_id, :new_parent_id)
        end

        def resolve_action!
          action = RecordingStudioApi.capability_action(params[:action_name])
          raise UnsupportedActionError, "Unknown API action #{params[:action_name]}" if action.nil?
          raise UnsupportedActionError, "#{action.name} is not enabled for #{resource_recording.recordable_type}" unless action.applicable_to?(resource_recording.recordable_type)

          action
        end

        def resource_recording
          @resource_recording ||= begin
            recordable_type = RecordingStudioApi.recordable_type_for_resource(params[:resource])
            raise RecordingStudioApi::NotFoundError, "Unknown API resource #{params[:resource]}" if recordable_type.blank?

            recording = current_root_recording.recordings_query(include_children: true).find_by(id: params[:id])
            raise RecordingStudioApi::NotFoundError, "Resource was not found in this API scope" if recording.nil?
            raise RecordingStudioApi::NotFoundError, "Resource type does not match #{recordable_type}" unless recording.recordable_type == recordable_type

            recording
          end
        end

        def serialize_result(action, result)
          serializer = action.serializer || RecordingStudioApi::Serializers::RecordingSerializer
          serializer.call(result)
        end
      end
    end
  end
end
