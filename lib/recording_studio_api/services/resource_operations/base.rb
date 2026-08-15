# frozen_string_literal: true

module RecordingStudioApi
  module Services
    module ResourceOperations
      class Base
        class << self
          def call(context)
            new(context).call
          end
        end

        def initialize(context)
          @context = context
        end

        private

        attr_reader :context

        def recording
          context.recording
        end

        def recordable_type
          context.recordable_type
        end

        def resource_name
          context.resource_name
        end

        def params
          context.params
        end

        def scoped_recordings
          context.scoped_recordings
        end

        def root_recording
          context.root_recording
        end

        def api_version
          context.api_version
        end

        def api_key
          context.api_key
        end

        def api_client
          context.api_client
        end

        def credential
          context.credential
        end

        def access_grant
          context.access_grant || RecordingStudioApi::AccessGrant.new(
            api_client: api_client,
            credential: credential,
            access_recording: context.access_recording,
            root_recording: root_recording
          )
        end

        def access_scope_recording
          access_grant.scope_recording || root_recording
        end

        def serialize_recording(target_recording, context: nil)
          RecordingStudioApi::Serializers::ResourceRecordingSerializer.call(
            target_recording,
            version: api_version,
            api: api_key,
            context: context
          )
        end

        def relationship_context_for(recordings, batch: false)
          RecordingStudioApi::RelationshipContext.for(
            recordings: recordings,
            include_values: params[:include],
            scoped_recordings: scoped_recordings,
            api_key: api_key,
            api_version: api_version,
            access_grant: access_grant,
            params: params,
            batch: batch
          )
        end

        def resource_attributes
          payload = request_payload
          if payload.key?("attributes") || payload.key?(:attributes)
            raise RecordingStudioApi::InvalidActionInputError.new(
              "The attributes envelope is no longer supported; send writable fields at the request body root",
              details: [
                {
                  attribute: :attributes,
                  message: "is not supported",
                  full_message: "Attributes is not supported",
                  type: :unsupported
                }
              ]
            )
          end

          normalized = payload.respond_to?(:to_h) ? payload.to_h : {}
          symbolized = normalized.respond_to?(:deep_symbolize_keys) ? normalized.deep_symbolize_keys : {}
          symbolized.slice(*allowed_attribute_keys)
        end

        def request_payload
          request_params = context.request_params || params
          request_params.respond_to?(:to_unsafe_h) ? request_params.to_unsafe_h : request_params.to_h
        end

        def allowed_attribute_keys
          registration = RecordingStudioApi.recordable_registration_for(recordable_type, api: api_key)
          Array(registration&.writable_attributes).map(&:to_sym)
        end

        def mutable_attribute_keys
          registration = RecordingStudioApi.recordable_registration_for(recordable_type, api: api_key)
          allowed_attribute_keys - Array(registration&.immutable_fields).map(&:to_sym)
        end

        def parent_recording_for_create
          return context.parent_recording if context.parent_recording

          parent_id = request_payload["parent_id"] || request_payload[:parent_id]
          if parent_id.blank?
            return access_scope_recording if root_recordable_type?

            raise RecordingStudioApi::InvalidActionInputError.new(
              "parent_id is required for #{recordable_type}",
              details: [
                {
                  attribute: :parent_id,
                  message: "is required",
                  full_message: "Parent is required",
                  type: :blank
                }
              ]
            )
          end

          parent_recording = scoped_recordings.find_by(id: parent_id)
          raise RecordingStudioApi::NotFoundError, "Parent resource was not found in this API scope" if parent_recording.nil?

          parent_recording
        end

        def root_recordable_type?
          RecordingStudio::RecordableDeclarations.root_allowed?(recordable_type)
        end

        def authorize_access!(target_recording, role:, include_trashed: false)
          access_grant.authorize!(recording: target_recording, role: role, include_trashed: include_trashed)
        end

        def delete_metadata
          {
            api_action: "delete",
            api_client_id: api_client.id,
            api_credential_id: credential.id
          }
        end

        def serialize_delete_result(serialized_recording, deleted_via:)
          serialized_recording.merge(
            deleted: true,
            deleted_via: deleted_via
          )
        end

        def destroy_resource!(target_recording)
          recordable = target_recording.recordable

          RecordingStudio::Recording.transaction do
            target_recording.destroy!

            if recordable.respond_to?(:destroy!) && recordable.respond_to?(:persisted?) && recordable.persisted?
              begin
                recordable.destroy!
              rescue ActiveRecord::ReadOnlyRecord
                # Immutable recordables are removed from API scope by deleting their recording.
              end
            end
          end
        end
      end
    end
  end
end