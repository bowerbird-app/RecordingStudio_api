# frozen_string_literal: true

module RecordingStudioApi
  module Api
    module V1
      class ResourceMetricsController < RecordingStudioApi::ApiController
        def index
          render_metric_result(RecordingStudioApi::Services::ResourceMetrics::Index)
        end

        def show
          render_metric_result(RecordingStudioApi::Services::ResourceMetrics::Show)
        end

        private

        def render_metric_result(service)
          result = service.call(resource_operation_context)
          render json: result.fetch(:json), status: result.fetch(:status, :ok)
        end

        def resource_operation_context
          recordable_type = resolve_recordable_type!
          RecordingStudioApi::ResourceOperationContext.new(
            recording: nil,
            recordable_type: recordable_type,
            resource_name: params[:resource].to_s,
            api_client: current_api_client,
            credential: current_api_credential,
            access_recording: current_access_recording,
            access_grant: current_access_grant,
            root_recording: current_root_recording,
            api_version: current_api_version,
            params: params,
            request_params: request.request_parameters,
            scoped_recordings: scoped_recordings,
            parent_recording: nil,
            idempotency_key: request.headers["Idempotency-Key"].presence
          )
        end

        def resolve_recordable_type!
          recordable_type = RecordingStudioApi.recordable_type_for_resource(params[:resource], api: current_api_key)
          raise RecordingStudioApi::NotFoundError, "Unknown API resource #{params[:resource]}" if recordable_type.blank?

          recordable_type
        end

        def scoped_recordings
          @scoped_recordings ||= current_access_grant.accessible_recordings
        end
      end
    end
  end
end
