# frozen_string_literal: true
# app/controllers/recording_studio_api/api/v1/relationship_resources_controller.rb

module RecordingStudioApi
  module Api
    module V1
      # Generic endpoints for registered relationships. Only relationships backed
      # by the Recording Studio child edge can be mutated by the engine; custom
      # sources remain application-owned and are intentionally read-only here.
      class RelationshipResourcesController < ResourcesController
        def index
          current_access_grant.authorize!(recording: parent_recording, role: :view)
          assert_readable!

          values = relationship_context.relationship_value(parent_recording, relationship_name, relationship)
          records = relationship_values(values).map { |value| serialize_relationship_value(value) }
          render json: { relationship: relationship_name, records: records }
        end

        def create
          assert_writable_children!
          child_type = resolve_child_type!
          assert_child_type_allowed!(child_type)
          assert_operation_enabled!(child_type, :create)

          result = RecordingStudioApi::Services::ResourceOperations::Create.call(
            relationship_operation_context(recordable_type: child_type)
          )
          render json: result.fetch(:json), status: result.fetch(:status, :created)
        end

        def update
          assert_writable_children!
          child = child_recording
          assert_operation_enabled!(child.recordable_type, :update)

          result = RecordingStudioApi::Services::ResourceOperations::Update.call(
            relationship_operation_context(recording: child, recordable_type: child.recordable_type)
          )
          render json: result.fetch(:json), status: result.fetch(:status, :ok)
        end

        def destroy
          assert_writable_children!
          child = child_recording(include_trashed: true)
          assert_operation_enabled!(child.recordable_type, :destroy)

          result = RecordingStudioApi::Services::ResourceOperations::Destroy.call(
            relationship_operation_context(recording: child, recordable_type: child.recordable_type)
          )
          render json: result.fetch(:json), status: result.fetch(:status, :ok)
        end

        private

        def parent_recording
          @parent_recording ||= resource_recording
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
            include_values: [relationship_name],
            scoped_recordings: scoped_recordings,
            api: current_api_key,
            version: current_api_version
          )
        end

        def serialize_relationship_value(value)
          return serialize_recording(value, context: relationship_context.nested) if recording?(value)

          serializer = relationship[:serializer]
          return call_relationship_serializer(serializer, value) if serializer.respond_to?(:call)

          project_relationship_value(value)
        end

        def call_relationship_serializer(serializer, value)
          serializer.call(value, context: relationship_context)
        rescue ArgumentError
          serializer.call(value)
        end

        def recording?(value)
          value.respond_to?(:recordable_type) && value.respond_to?(:recordable) && value.respond_to?(:id)
        end

        def relationship_values(value)
          return [] if value.nil?
          return value if value.is_a?(Array)

          [value]
        end

        def project_relationship_value(value)
          fields = relationship[:fields]
          return {} unless fields

          resolved_fields = if fields.respond_to?(:call)
                              normalize_hash(call_relationship_serializer(fields, value))
                            else
                              fields.each_with_object({}) do |(name, definition), output|
                                output[name.to_s] = resolve_relationship_field(value, name, definition)
                              end
                            end
          relationship[:output_keys].each_with_object({}) do |key, output|
            output[key.to_sym] = resolved_fields[key] if resolved_fields.key?(key)
          end
        end

        def resolve_relationship_field(value, name, definition)
          return call_relationship_serializer(definition, value) if definition.respond_to?(:call)
          return read_relationship_field(value, name, definition) unless definition.is_a?(Hash)

          resolver = definition[:resolver] || definition[:value]
          return call_relationship_serializer(resolver, value) if resolver.respond_to?(:call)
          return resolver unless resolver.nil?

          read_relationship_field(value, name, definition[:source] || definition[:method] || name)
        end

        def read_relationship_field(value, name, source)
          return value.public_send(source) if source.respond_to?(:to_sym) && value.respond_to?(source)
          return value[source] if value.respond_to?(:[]) && value.respond_to?(:key?) && value.key?(source)
          return value[source.to_s] if value.respond_to?(:[]) && value.respond_to?(:key?) && value.key?(source.to_s)

          value.public_send(name) if value.respond_to?(name)
        end

        def normalize_hash(value)
          return {} unless value.respond_to?(:to_h)

          value.to_h.each_with_object({}) { |(key, item), output| output[key.to_s] = item }
        end

        def child_recording(include_trashed: false)
          child = child_scope(include_trashed: include_trashed).find_by(id: params[:relationship_id])
          raise RecordingStudioApi::NotFoundError, "Relationship resource was not found in this API scope" if child.nil?

          child
        end

        def child_scope(include_trashed: false)
          relation = scoped_recordings(include_trashed: include_trashed).where(parent_recording_id: parent_recording.id)
          types = relationship.fetch(:types)
          types.empty? ? relation : relation.where(recordable_type: types)
        end

        def assert_readable!
          return if relationship.fetch(:read)

          raise RecordingStudioApi::UnsupportedActionError,
                "#{relationship_name} is not readable for #{parent_recording.recordable_type}"
        end

        def assert_writable_children!
          current_access_grant.authorize!(recording: parent_recording, role: :edit)
          unless relationship.fetch(:source) == :children
            raise RecordingStudioApi::UnsupportedActionError, "#{relationship_name} is not a writable child relationship"
          end
          return if relationship.fetch(:write) && !parent_registration.immutable_relationships.include?(relationship_name)

          raise RecordingStudioApi::UnsupportedActionError,
                "#{relationship_name} is immutable for #{parent_recording.recordable_type}"
        end

        def resolve_child_type!
          requested_type = params[:type].to_s
          recordable_type = RecordingStudioApi.recordable_type_for_resource(requested_type, api: current_api_key)
          raise RecordingStudioApi::NotFoundError, "Unknown relationship resource #{requested_type}" if recordable_type.blank?

          recordable_type
        end

        def assert_child_type_allowed!(recordable_type)
          allowed_types = relationship.fetch(:types)
          return if allowed_types.empty? || allowed_types.include?(recordable_type)

          raise RecordingStudioApi::UnsupportedActionError,
                "#{recordable_type} is not allowed for #{relationship_name} on #{parent_recording.recordable_type}"
        end

        def assert_operation_enabled!(recordable_type, operation)
          registration = RecordingStudioApi.recordable_registration_for(recordable_type, api: current_api_key)
          return unless registration && !registration.supports_operation?(operation)

          raise RecordingStudioApi::UnsupportedActionError, "#{operation} is not enabled for #{recordable_type}"
        end

        def relationship_operation_context(recording: nil, recordable_type:)
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
            params: params.merge(parent_id: parent_recording.id),
            scoped_recordings: scoped_recordings
          )
        end
      end
    end
  end
end
