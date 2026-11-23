# frozen_string_literal: true

# app/controllers/recording_studio_api/api/v1/relationship_resources_controller.rb

module RecordingStudioApi
  module Api
    module V1
      # Generic endpoints for configured, direct child collections.
      class RelationshipResourcesController < ResourcesController
        def index
          if (handler = nested_resource_handler(:index))
            render_registered_resource_handler!(handler, nested_handler_context(:index))
            return
          end

          assert_nested_operation!(:index, role: :view)

          pagination = RecordingStudioApi::Services::PaginateResourceCollection.call(
            relation: child_scope,
            resource: child_resource_name,
            recordable_type: relationship.child_type,
            limit: params[:limit],
            pagination_token: params[:pagination_token],
            sort: params[:sort],
            order: params[:order],
            count: params[:count],
            include_total: params[:include_total],
            api: current_api_key,
            scope_key: "client:#{current_api_client.id}"
          )
          raise RecordingStudioApi::InvalidPaginationTokenError, pagination.error if pagination.failure?

          render json: pagination.value.response_body { |rows, meta|
            children = authorized_children(rows)
            {
              resource: child_resource_name,
              type: relationship.child_type.demodulize,
              records: children.map { |child| serialize_recording(child, context: relationship_context.nested) },
              meta: meta
            }
          }
        end

        def show
          if (handler = nested_resource_handler(:show))
            render_registered_resource_handler!(handler, nested_handler_context(:show))
            return
          end

          assert_nested_operation!(:show, role: :view)
          child = child_recording
          authorize_child!(child)

          render json: serialize_recording(child, context: relationship_context.nested)
        end

        def create
          if (handler = nested_resource_handler(:create))
            reject_nested_type_or_parent_input!
            render_registered_resource_handler!(handler, nested_handler_context(:create), operation_name: :create)
            return
          end

          assert_nested_operation!(:create, role: :edit)
          reject_nested_type_or_parent_input!

          result = run_authorized_handler do
            RecordingStudioApi::Services::ResourceOperations::Create.call(
              relationship_operation_context(recordable_type: relationship.child_type)
            )
          end
          return if performed?

          render json: result.fetch(:json), status: result.fetch(:status, :created)
        end

        def update
          if (handler = nested_resource_handler(:update))
            reject_nested_parent_input!
            render_registered_resource_handler!(handler, nested_handler_context(:update))
            return
          end

          assert_nested_operation!(:update, role: :edit)
          reject_nested_parent_input!
          child = child_recording
          authorize_child!(child)

          result = run_authorized_handler do
            RecordingStudioApi::Services::ResourceOperations::Update.call(
              relationship_operation_context(recording: child, recordable_type: relationship.child_type)
            )
          end
          return if performed?

          render json: result.fetch(:json), status: result.fetch(:status, :ok)
        end

        def destroy
          if (handler = nested_resource_handler(:destroy))
            render_registered_resource_handler!(handler, nested_handler_context(:destroy))
            return
          end

          assert_nested_operation!(:destroy, role: :edit, include_trashed: true)
          child = child_recording(include_trashed: true)
          authorize_child!(child)

          result = run_authorized_handler do
            RecordingStudioApi::Services::ResourceOperations::Destroy.call(
              relationship_operation_context(recording: child, recordable_type: relationship.child_type)
            )
          end
          return if performed?

          render json: result.fetch(:json), status: result.fetch(:status, :ok)
        end

        private

        def parent_recording(include_trashed: false)
          @parent_recordings ||= {}
          @parent_recordings[include_trashed] ||= RecordingStudioApi::ScopedRecording.find!(
            access_grant: current_access_grant,
            id: params[:parent_id],
            recordable_type: resolve_recordable_type!,
            include_trashed: include_trashed,
            missing: "Parent resource was not found in this API scope",
            type_mismatch: "Parent resource type does not match #{resolve_recordable_type!}"
          )
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
          child = RecordingStudioApi::ScopedRecording.find!(
            access_grant: current_access_grant,
            id: params[:relationship_id],
            recordable_type: relationship.child_type,
            include_trashed: include_trashed,
            missing: "Relationship resource was not found in this API scope"
          )
          return child if child.parent_recording_id == parent_recording.id

          raise RecordingStudioApi::NotFoundError, RecordingStudioApi::ScopedRecording.unexpected_id_message(
            relationship.child_type,
            api: current_api_key
          )
        end

        def child_scope(include_trashed: false)
          current_access_grant.accessible_recordings(
            include_trashed: include_trashed,
            scope: RecordingStudio::Recording.unscoped.where(
              parent_recording_id: parent_recording.id,
              recordable_type: relationship.child_type
            )
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
          assert_direct_child_endpoint!(operation)
          assert_operation_enabled!(relationship.child_type, operation)
          relationship_context.authorize_relationship!(parent_recording, relationship_name, relationship)
        end

        def assert_direct_child_endpoint!(operation, target = relationship)
          unless target.source == :children && target.many
            raise RecordingStudioApi::UnsupportedActionError,
                  "#{relationship_name} is not a direct child collection"
          end
          return if target.endpoints.include?(operation.to_sym)

          raise RecordingStudioApi::UnsupportedActionError, "#{operation} is not enabled for #{relationship_name}"
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

        def nested_resource_handler(operation_name)
          relationship = declared_parent_relationship
          return unless relationship&.child_type

          registration = RecordingStudioApi.recordable_registration_for(relationship.child_type, api: current_api_key)
          return unless registration&.supports_operation?(operation_name)

          RecordingStudioApi.resource_handler(relationship.child_type, operation_name, api: current_api_key)
        end

        def declared_parent_relationship
          parent_type = resolve_recordable_type!
          RecordingStudioApi.recordable_registration_for(parent_type, api: current_api_key)
                            &.relationships
                            &.[](relationship_name)
        end

        def nested_handler_context(operation_name)
          relationship = declared_parent_relationship
          registration = RecordingStudioApi.resource_handler_registration(
            relationship.child_type,
            operation_name,
            api: current_api_key
          )
          parent, child = nested_handler_targets(operation_name, registration)
          build_relationship_operation_context(
            recordable_type: relationship.child_type,
            recording: child,
            parent_recording: parent
          )
        end

        def nested_handler_targets(operation_name, registration)
          if RecordingStudioApi::HandlerScope.resource_opt_out?(registration&.owns_scoping?, operation_name)
            assert_direct_child_endpoint!(operation_name, declared_parent_relationship)
            return [nil, nil]
          end

          assert_direct_child_endpoint!(operation_name)
          role = RecordingStudioApi::HandlerScope.resource_role(operation_name)
          include_trashed = RecordingStudioApi::HandlerScope.dispatch_include_trashed?(
            include_trashed: registration.include_trashed,
            trashed_semantics: registration.trashed_semantics,
            role: role
          )
          if %i[show update destroy].include?(operation_name.to_sym)
            parent = parent_recording
            child = child_recording(include_trashed: include_trashed)
            current_access_grant.authorize!(recording: child, role: role, include_trashed: include_trashed)
            authorize_nested_relationship!(parent, include_trashed: false)
            authorize_child!(child)
            [parent, child]
          else
            parent = parent_recording(include_trashed: include_trashed)
            current_access_grant.authorize!(recording: parent, role: role, include_trashed: include_trashed)
            authorize_nested_relationship!(parent, include_trashed: include_trashed)
            [parent, nil]
          end
        end

        def authorize_nested_relationship!(parent, include_trashed:)
          RecordingStudioApi::RelationshipContext.for(
            recordings: [parent],
            include_values: nil,
            scoped_recordings: scoped_recordings(include_trashed: include_trashed),
            api_key: current_api_key,
            api_version: current_api_version,
            access_grant: current_access_grant,
            params: {}
          ).authorize_relationship!(parent, relationship_name, relationship)
        end

        def relationship_operation_context(recordable_type:, recording: nil)
          build_relationship_operation_context(
            recordable_type: recordable_type,
            recording: recording,
            parent_recording: parent_recording
          )
        end

        def build_relationship_operation_context(recordable_type:, recording:, parent_recording:)
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
            idempotency_key: request.headers["Idempotency-Key"].presence,
            id: params[:id],
            parent_id: params[:parent_id],
            relationship_id: params[:relationship_id]
          )
        end
      end
    end
  end
end
