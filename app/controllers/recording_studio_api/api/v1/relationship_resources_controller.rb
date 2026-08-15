# frozen_string_literal: true

# app/controllers/recording_studio_api/api/v1/relationship_resources_controller.rb

module RecordingStudioApi
  module Api
    module V1
      # Generic endpoints for configured, direct child collections.
      class RelationshipResourcesController < ResourcesController
        def index
          assert_nested_operation!(:index, role: :view)

          pagination = RecordingStudioApi::Services::PaginateResourceCollection.call(
            relation: child_scope,
            resource: child_resource_name,
            recordable_type: relationship.child_type,
            limit: params[:limit],
            pagination_token: params[:pagination_token],
            sort: params[:sort],
            order: params[:order],
            api: current_api_key,
            scope_key: "client:#{current_api_client.id}"
          )
          raise RecordingStudioApi::InvalidPaginationTokenError, pagination.error if pagination.failure?

          payload = pagination.value
          children = authorized_children(payload.fetch(:rows))
          render json: {
            resource: child_resource_name,
            type: relationship.child_type.demodulize,
            records: children.map { |child| serialize_recording(child, context: relationship_context.nested) },
            meta: payload.fetch(:meta)
          }
        end

        def show
          assert_nested_operation!(:show, role: :view)
          child = child_recording
          authorize_child!(child)

          render json: serialize_recording(child, context: relationship_context.nested)
        end

        def create
          assert_nested_operation!(:create, role: :edit)
          reject_nested_type_or_parent_input!

          result = RecordingStudioApi::Services::ResourceOperations::Create.call(
            relationship_operation_context(recordable_type: relationship.child_type)
          )
          render json: result.fetch(:json), status: result.fetch(:status, :created)
        end

        def update
          assert_nested_operation!(:update, role: :edit)
          reject_nested_parent_input!
          child = child_recording
          authorize_child!(child)

          result = RecordingStudioApi::Services::ResourceOperations::Update.call(
            relationship_operation_context(recording: child, recordable_type: relationship.child_type)
          )
          render json: result.fetch(:json), status: result.fetch(:status, :ok)
        end

        def destroy
          assert_nested_operation!(:destroy, role: :edit, include_trashed: true)
          child = child_recording(include_trashed: true)
          authorize_child!(child)

          result = RecordingStudioApi::Services::ResourceOperations::Destroy.call(
            relationship_operation_context(recording: child, recordable_type: relationship.child_type)
          )
          render json: result.fetch(:json), status: result.fetch(:status, :ok)
        end

        private

        def parent_recording
          @parent_recording ||= begin
            recordable_type = resolve_recordable_type!
            recording = scoped_recordings.find_by(id: params[:parent_id])
            raise RecordingStudioApi::NotFoundError, "Parent resource was not found in this API scope" if recording.nil?
            raise RecordingStudioApi::NotFoundError, "Parent resource type does not match #{recordable_type}" unless recording.recordable_type == recordable_type

            recording
          end
        end

        def relationship_name = params[:relationship].to_s

        def relationship
          @relationship ||= parent_registration&.relationships&.fetch(relationship_name, nil) ||
                            raise(
                              RecordingStudioApi::UnsupportedActionError,
                              "#{relationship_name} is not enabled for #{parent_recording.recordable_type}"
                            )
        end

        def parent_registration
          RecordingStudioApi.recordable_registration_for(parent_recording.recordable_type, api: current_api_key)
        end

        def relationship_context
          @relationship_context ||= RecordingStudioApi::RelationshipContext.for(
            recordings: [parent_recording],
            include_values: nil,
            scoped_recordings: scoped_recordings,
            api_key: current_api_key,
            api_version: current_api_version,
            access_grant: current_access_grant,
            params: {}
          )
        end

        def child_recording(include_trashed: false)
          child = child_scope(include_trashed: include_trashed).find_by(id: params[:relationship_id])
          raise RecordingStudioApi::NotFoundError, "Relationship resource was not found in this API scope" if child.nil?

          child
        end

        def child_scope(include_trashed: false)
          scoped_recordings(include_trashed: include_trashed).where(
            parent_recording_id: parent_recording.id,
            recordable_type: relationship.child_type
          )
        end

        def authorized_children(children)
          children.select do |child|
            authorize_child!(child)
            true
          rescue RecordingStudioApi::NotFoundError
            false
          end
        end

        def authorize_child!(child)
          relationship_context.authorized_targets([child], parent_recording, relationship_name, relationship)
          child
        rescue RecordingStudioApi::AuthorizationError
          raise RecordingStudioApi::NotFoundError, "Relationship resource was not found in this API scope"
        end

        def assert_nested_operation!(operation, role:, include_trashed: false)
          current_access_grant.authorize!(recording: parent_recording, role: role, include_trashed: include_trashed)
          unless relationship.source == :children && relationship.many
            raise RecordingStudioApi::UnsupportedActionError,
                  "#{relationship_name} is not a direct child collection"
          end
          raise RecordingStudioApi::UnsupportedActionError, "#{operation} is not enabled for #{relationship_name}" unless relationship.endpoints.include?(operation)

          assert_operation_enabled!(relationship.child_type, operation)
          relationship_context.authorize_relationship!(parent_recording, relationship_name, relationship)
        end

        def reject_nested_type_or_parent_input!
          reject_nested_type_input!
          reject_nested_parent_input!
        end

        def reject_nested_type_input!
          raise RecordingStudioApi::InvalidActionInputError, "type is not permitted for nested relationship creation" if params.key?(:type)
        end

        def reject_nested_parent_input!
          return unless request.request_parameters.key?("parent_id") || request.request_parameters.key?(:parent_id)

          raise RecordingStudioApi::InvalidActionInputError, "parent_id is not permitted for nested relationship operations"
        end

        def child_resource_name
          RecordingStudioApi.resource_name_for(relationship.child_type)
        end

        def assert_operation_enabled!(recordable_type, operation)
          registration = RecordingStudioApi.recordable_registration_for(recordable_type, api: current_api_key)
          return if registration&.supports_operation?(operation)

          raise RecordingStudioApi::UnsupportedActionError, "#{operation} is not enabled for #{recordable_type}"
        end

        def relationship_operation_context(recordable_type:, recording: nil)
          RecordingStudioApi::ResourceOperationContext.new(
            recording: recording,
            recordable_type: recordable_type,
            resource_name: RecordingStudioApi.resource_name_for(recordable_type),
            api_client: current_api_client,
            credential: current_api_credential,
            access_recording: current_access_recording,
            access_grant: current_access_grant,
            root_recording: current_root_recording,
            api_version: current_api_version,
            params: params.to_unsafe_h,
            request_params: request.request_parameters,
            scoped_recordings: scoped_recordings,
            parent_recording: parent_recording,
            idempotency_key: request.headers["Idempotency-Key"].presence
          )
        end
      end
    end
  end
end
