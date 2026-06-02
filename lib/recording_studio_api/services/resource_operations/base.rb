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

        def serialize_recording(target_recording)
          RecordingStudioApi::Serializers::ResourceRecordingSerializer.call(target_recording)
        end

        def resource_attributes
          payload = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : {}
          attributes = payload["attributes"]
          attributes = payload[:attributes] if attributes.nil?
          attributes = payload if attributes.nil?

          normalized = attributes.respond_to?(:to_h) ? attributes.to_h : {}
          symbolized = normalized.respond_to?(:deep_symbolize_keys) ? normalized.deep_symbolize_keys : {}
          symbolized.slice(*allowed_attribute_keys)
        end

        def allowed_attribute_keys
          registration = RecordingStudioApi.recordable_registration_for(recordable_type)
          schema_properties = registration&.openapi&.dig(:details_schema, :properties)

          if schema_properties.respond_to?(:keys) && schema_properties.keys.any?
            schema_properties.keys.map(&:to_sym)
          else
            recordable_class = recordable_type.safe_constantize
            return [] unless recordable_class.respond_to?(:column_names)

            recordable_class.column_names.map(&:to_sym) - %i[id created_at updated_at]
          end
        end

        def parent_recording_for_create
          return access_scope_recording if params[:parent_id].blank?

          parent_recording = scoped_recordings.find_by(id: params[:parent_id])
          raise RecordingStudioApi::NotFoundError, "Parent resource was not found in this API scope" if parent_recording.nil?

          parent_recording
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