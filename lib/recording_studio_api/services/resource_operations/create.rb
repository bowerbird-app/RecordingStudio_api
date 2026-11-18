# frozen_string_literal: true

module RecordingStudioApi
  module Services
    module ResourceOperations
      class Create < Base
        def call
          with_idempotency { create_record }
        rescue RecordingStudio::InvalidParent => e
          raise invalid_parent_input_error(e.message)
        end

        private

        def with_idempotency(&block)
          key = context.idempotency_key
          return block.call if key.blank?

          RecordingStudioApi::Idempotency.replay(
            api: api_key,
            client_id: idempotency_client_id,
            key: key,
            fingerprint: request_fingerprint,
            &block
          )
        end

        def create_record
          recordable_class = recordable_type.safe_constantize
          raise RecordingStudioApi::NotFoundError, "Unknown API resource #{resource_name}" if recordable_class.nil?

          parent_recording = parent_recording_for_create
          raise missing_parent_error if parent_recording.nil?

          authorize_access!(parent_recording, role: :edit)
          assert_parent_allowed!(parent_recording)
          created_recording = record_child!(recordable_class, parent_recording)

          {
            json: serialize_recording(created_recording, context: relationship_context_for([created_recording])),
            status: :created
          }
        end

        def request_fingerprint
          RecordingStudioApi::IdempotencyStore.fingerprint(
            method: "POST",
            path: fingerprint_path,
            params: request_payload
          )
        end

        def fingerprint_path
          parent = context.parent_recording
          parent ? "#{resource_name}/#{parent.id}" : resource_name.to_s
        end

        def record_child!(recordable_class, parent_recording)
          impersonator = write_impersonator
          RecordingStudio.root_recording_or_self(parent_recording).record(
            recordable_class,
            actor: write_actor,
            metadata: context.with_authorized_by,
            parent_recording: parent_recording,
            **(impersonator ? { impersonator: impersonator } : {})
          ) do |recordable|
            recordable.assign_attributes(resource_attributes)
          end
        end

        def assert_parent_allowed!(parent_recording)
          RecordingStudio.assert_parent_allowed!(child_type: recordable_type, parent_recording: parent_recording)
        end

        def missing_parent_error
          message = "A parent recording is required to create #{recordable_type}"
          RecordingStudioApi::InvalidActionInputError.new(
            message,
            details: [
              {
                attribute: :parent_id,
                message: "is required",
                full_message: message,
                type: :blank
              }
            ]
          )
        end

        def invalid_parent_input_error(message)
          RecordingStudioApi::InvalidParentInput.call(message, recordable_type: recordable_type)
        end
      end
    end
  end
end
