# frozen_string_literal: true

module RecordingStudioApi
  module Api
    module V1
      class ResourcesController < RecordingStudioApi::ApiController
        def index
          return render json: root_resources_payload if params[:resource].blank?

          render_dispatched_resource_action!(:index)
        end

        def show
          render_dispatched_resource_action!(:show)
        end

        def create
          render_dispatched_resource_action!(:create)
        end

        def update
          render_dispatched_resource_action!(:update)
        end

        def destroy
          render_dispatched_resource_action!(:destroy)
        end

        private

        def resource_recording(include_trashed: false)
          @resource_recordings ||= {}
          @resource_recordings[include_trashed] ||= RecordingStudioApi::ScopedRecording.find!(
            access_grant: current_access_grant,
            id: params[:id],
            recordable_type: resolve_recordable_type!,
            include_trashed: include_trashed
          )
        end

        # Built when a caller queries it. A list that already passed its scope
        # into `authorized_recordings` does not pay for this one as well.
        def scoped_recordings(include_trashed: false)
          @scoped_recordings ||= {}
          @scoped_recordings[include_trashed] ||= -> { current_access_grant.accessible_recordings(include_trashed: include_trashed) }
        end

        def resolve_recordable_type!
          recordable_type = RecordingStudioApi.recordable_type_for_resource(params[:resource], api: current_api_key)
          raise RecordingStudioApi::NotFoundError, "Unknown API resource #{params[:resource]}" if recordable_type.blank?

          recordable_type
        end

        def serialize_recording(recording, context: nil)
          RecordingStudioApi::Serializers::ResourceRecordingSerializer.call(
            recording,
            version: current_api_version,
            api: current_api_key,
            context: context
          )
        end

        def render_dispatched_resource_action!(operation_name)
          operation = resolve_resource_action!(operation_name)
          recordable_type = resolve_recordable_type!
          handler = RecordingStudioApi.resource_handler(recordable_type, operation_name, api: current_api_key)
          if handler
            registration = RecordingStudioApi.resource_handler_registration(recordable_type, operation_name, api: current_api_key)
            render_registered_resource_handler!(
              handler,
              registered_resource_context(operation_name, recordable_type, registration)
            )
            return
          end

          context = resource_operation_context(recording: builtin_member_recording_for(operation_name))
          result = run_authorized_handler { operation.handler.call(context) }
          return if performed?

          render json: result.fetch(:json), status: result.fetch(:status, :ok)
        end

        def render_registered_resource_handler!(handler, context)
          result = run_authorized_handler { handler.call(context) }
          return if performed?

          render json: result.fetch(:json), status: result.fetch(:status, :ok)
        end

        def registered_resource_context(operation_name, recordable_type, registration)
          recording = RecordingStudioApi::HandlerGuard.resource!(
            access_grant: current_access_grant,
            recordable_type: recordable_type,
            action_name: operation_name,
            id: params[:id],
            registration: registration
          ).recording
          resource_operation_context(recording: recording, recordable_type: recordable_type)
        end

        def builtin_member_recording_for(operation_name)
          case operation_name
          when :show, :update
            resource_recording
          when :destroy
            resource_recording(include_trashed: true)
          end
        end

        def resolve_resource_action!(operation_name)
          operation = RecordingStudioApi.resource_action(operation_name, version: current_api_version, api: current_api_key)
          raise RecordingStudioApi::UnsupportedActionError, "Unknown API resource operation #{operation_name}" if operation.nil?

          recordable_type = resolve_recordable_type!
          registration = RecordingStudioApi.recordable_registration_for(recordable_type, api: current_api_key)
          raise RecordingStudioApi::UnsupportedActionError, "#{operation_name} is not enabled for #{recordable_type}" if registration && !registration.supports_operation?(operation_name)

          raise RecordingStudioApi::UnsupportedActionError, "#{operation.name} is not enabled for #{recordable_type}" unless operation.applicable_to?(recordable_type)

          operation
        end

        def resource_operation_context(recording: nil, recordable_type: resolve_recordable_type!)
          RecordingStudioApi::ResourceOperationContext.new(
            recording: recording,
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
            idempotency_key: request.headers["Idempotency-Key"].presence,
            id: params[:id],
            parent_id: params[:parent_id],
            relationship_id: params[:relationship_id]
          )
        end

        def root_resources_payload
          {
            resources: RecordingStudioApi.api_recordable_types(api: current_api_key).map do |recordable_type|
              {
                name: RecordingStudioApi.resource_name_for(recordable_type),
                type: recordable_type.demodulize.underscore
              }
            end
          }
        end
      end
    end
  end
end
