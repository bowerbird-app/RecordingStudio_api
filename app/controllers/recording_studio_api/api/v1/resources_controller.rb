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
          render_dispatched_resource_action!(:show, recording: resource_recording)
        end

        def create
          render_dispatched_resource_action!(:create)
        end

        def update
          render_dispatched_resource_action!(:update, recording: resource_recording)
        end

        def destroy
          render_dispatched_resource_action!(:destroy, recording: resource_recording(include_trashed: true))
        end

        private

        def resource_recording(include_trashed: false)
          @resource_recordings ||= {}
          @resource_recordings[include_trashed] ||= begin
            recordable_type = resolve_recordable_type!
            recording = scoped_recordings(include_trashed: include_trashed).find_by(id: params[:id])
            raise RecordingStudioApi::NotFoundError, "Resource was not found in this API scope" if recording.nil?
            raise RecordingStudioApi::NotFoundError, "Resource type does not match #{recordable_type}" unless recording.recordable_type == recordable_type

            recording
          end
        end

        def scoped_recordings(include_trashed: false)
          @scoped_recordings ||= {}
          @scoped_recordings[include_trashed] ||= current_access_grant.accessible_recordings(include_trashed: include_trashed)
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

        def destroy_resource!(recording)
          recordable = recording.recordable

          RecordingStudio::Recording.transaction do
            recording.destroy!

            if recordable.respond_to?(:destroy!) && recordable.respond_to?(:persisted?) && recordable.persisted?
              begin
                recordable.destroy!
              rescue ActiveRecord::ReadOnlyRecord
                # Immutable recordables are removed from API scope by deleting their recording.
              end
            end
          end
        end

        def invoke_resource_method(target, method_name, **kwargs)
          target.public_send(method_name, **kwargs)
        rescue ArgumentError
          target.public_send(method_name)
        end

        def delete_metadata
          {
            api_action: "delete",
            api_client_id: current_api_client.id,
            api_credential_id: current_api_credential.id
          }
        end

        def serialize_delete_result(serialized_recording, deleted_via:)
          serialized_recording.merge(
            deleted: true,
            deleted_via: deleted_via
          )
        end

        def render_dispatched_resource_action!(operation_name, recording: nil)
          operation = resolve_resource_action!(operation_name)
          result = operation.handler.call(resource_operation_context(recording: recording))
          render json: result.fetch(:json), status: result.fetch(:status, :ok)
        end

        def render_dispatched_capability_action!(action_name, recording:)
          action = resolve_capability_action!(action_name, recordable_type: recording.recordable_type)
          context = resource_operation_context(recording: recording, recordable_type: recording.recordable_type)
          authorize_capability_action!(action, context)
          result = action.handler.call(context)
          render json: result.fetch(:json), status: result.fetch(:status, :ok)
        end

        def authorize_capability_action!(action, context)
          required_role = RecordingStudioApi.configuration.capability_action_role_for(
            action: action,
            recording: context.recording,
            api_client: context.api_client,
            access_grant: context.access_grant
          )
          return if required_role.nil?

          context.access_grant.authorize!(recording: context.recording, role: required_role, include_trashed: true)
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

        def resolve_capability_action!(action_name, recordable_type:)
          action = RecordingStudioApi.capability_action(action_name, version: current_api_version, api: current_api_key)
          raise RecordingStudioApi::UnsupportedActionError, "Unknown API action #{action_name}" if action.nil?
          raise RecordingStudioApi::UnsupportedActionError, "#{action.name} is not enabled for #{recordable_type}" unless action.applicable_to?(recordable_type)
          raise RecordingStudioApi::UnsupportedActionError, "#{action.name} is not enabled for #{recordable_type}" unless RecordingStudioApi.capability_action_enabled_for?(action, recordable_type, api: current_api_key)

          action
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
            parent_recording: nil
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
