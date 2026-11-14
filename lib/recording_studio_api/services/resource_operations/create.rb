# frozen_string_literal: true

module RecordingStudioApi
  module Services
    module ResourceOperations
      class Create < Base
        def call
          if (cached = cached_idempotent_response)
            return cached
          end

          recordable_class = recordable_type.safe_constantize
          raise RecordingStudioApi::NotFoundError, "Unknown API resource #{resource_name}" if recordable_class.nil?

          parent_recording = parent_recording_for_create
          raise missing_parent_error if parent_recording.nil?

          authorize_access!(parent_recording, role: :edit)
          assert_parent_allowed!(parent_recording)
          created_recording = record_child!(recordable_class, parent_recording)

          result = {
            json: serialize_recording(created_recording, context: relationship_context_for([created_recording])),
            status: :created
          }
          store_idempotent_response(result)
          result
        rescue RecordingStudio::InvalidParent => e
          raise invalid_parent_input_error(e.message)
        end

        private

        def cached_idempotent_response
          key = context.idempotency_key
          return nil if key.blank?

          payload = RecordingStudioApi::IdempotencyStore.fetch(
            api: api_key,
            client_id: idempotency_client_id,
            key: key
          )
          return nil if payload.blank?

          {
            json: payload.fetch("json"),
            status: payload.fetch("status", "created").to_sym
          }
        end

        def store_idempotent_response(result)
          key = context.idempotency_key
          return if key.blank?

          RecordingStudioApi::IdempotencyStore.write(
            api: api_key,
            client_id: idempotency_client_id,
            key: key,
            payload: result.fetch(:json),
            status: result.fetch(:status, :created).to_s
          )
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
