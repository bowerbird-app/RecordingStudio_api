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

        def trash_index
          recordings = scoped_recordings(include_trashed: true)
            .where.not(trashed_at: nil)
            .order(created_at: :asc, id: :asc)
            .limit(trash_limit)

          render json: {
            resource: "trash",
            data: recordings.map { |recording| serialize_recording(recording) },
            meta: {
              limit: trash_limit,
              returned: recordings.length
            }
          }
        end

        def trash_show
          render json: { data: serialize_recording(trashed_resource_recording) }
        end

        def trash_restore
          render_dispatched_capability_action!(:trash_restore, recording: trashed_resource_recording)
        end

        def trash_destroy
          render_dispatched_capability_action!(:trash_destroy, recording: trashed_resource_recording)
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
          recordable_type = RecordingStudioApi.recordable_type_for_resource(params[:resource])
          raise RecordingStudioApi::NotFoundError, "Unknown API resource #{params[:resource]}" if recordable_type.blank?

          recordable_type
        end

        def serialize_recording(recording)
          RecordingStudioApi::Serializers::ResourceRecordingSerializer.call(recording)
        end

        def trash_resource!(recording)
          if recording.respond_to?(:trash!)
            invoke_delete_method(recording, :trash!, actor: current_api_client, metadata: delete_metadata)
            return "trashed"
          end

          recordable = recording.recordable
          if recordable.respond_to?(:trash!)
            invoke_delete_method(recordable, :trash!, actor: current_api_client, metadata: delete_metadata)
            return "trashed"
          end

          if recording.respond_to?(:has_attribute?) && recording.has_attribute?(:trashed_at)
            recording.update!(trashed_at: Time.current)
            return "trashed"
          end

          raise RecordingStudioApi::UnsupportedActionError, "Delete is not supported for #{recording.recordable_type}"
        end

        def trashable_recordable_type?(recordable_type)
          recordable_class = recordable_type.safe_constantize
          return true if recordable_class && recordable_class.instance_methods.include?(:trash!)

          return false unless defined?(RecordingStudio) && RecordingStudio.respond_to?(:capability_enabled?)

          RecordingStudio.capability_enabled?(:trashable, for: recordable_type)
        end

        def ensure_trashable_recordable_type!(recordable_type)
          return if trashable_recordable_type?(recordable_type)

          raise RecordingStudioApi::UnsupportedActionError, "Trash is not supported for #{recordable_type}"
        end

        def trashed_resource_recording
          recording = scoped_recordings(include_trashed: true).find_by(id: params[:id])
          raise RecordingStudioApi::NotFoundError, "Resource was not found in this API scope" if recording.nil?
          raise RecordingStudioApi::NotFoundError, "Trashed resource was not found in this API scope" if recording.trashed_at.blank?

          recording
        end

        def trash_limit
          requested = params[:limit].to_i
          default_limit = RecordingStudioApi.configuration.pagination_default_limit.to_i
          max_limit = RecordingStudioApi.configuration.pagination_max_limit.to_i

          resolved_default = default_limit.positive? ? default_limit : 50
          resolved_max = max_limit.positive? ? max_limit : 100
          resolved_requested = requested.positive? ? requested : resolved_default

          [resolved_requested, resolved_max].min
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

        def invoke_delete_method(target, method_name, **kwargs)
          invoke_resource_method(target, method_name, **kwargs)
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
          result = action.handler.call(resource_operation_context(recording: recording, recordable_type: recording.recordable_type))
          render json: result.fetch(:json), status: result.fetch(:status, :ok)
        end

        def resolve_resource_action!(operation_name)
          operation = RecordingStudioApi.resource_action(operation_name)
          raise RecordingStudioApi::UnsupportedActionError, "Unknown API resource operation #{operation_name}" if operation.nil?

          recordable_type = resolve_recordable_type!
          raise RecordingStudioApi::UnsupportedActionError, "#{operation.name} is not enabled for #{recordable_type}" unless operation.applicable_to?(recordable_type)

          operation
        end

        def resolve_capability_action!(action_name, recordable_type:)
          action = RecordingStudioApi.capability_action(action_name)
          raise RecordingStudioApi::UnsupportedActionError, "Unknown API action #{action_name}" if action.nil?
          raise RecordingStudioApi::UnsupportedActionError, "#{action.name} is not enabled for #{recordable_type}" unless action.applicable_to?(recordable_type)

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
            params: params,
            scoped_recordings: scoped_recordings
          )
        end

        def root_resources_payload
          {
            resources: RecordingStudioApi.api_recordable_types.map do |recordable_type|
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
