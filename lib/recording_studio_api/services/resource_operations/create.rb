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
          authorize_access!(parent_recording, role: :edit)

          created_recording = nil
          RecordingStudio::Recording.transaction do
            assert_parent_allowed!(parent_recording)
            recordable = recordable_class.create!(resource_attributes)
            created_recording = RecordingStudio::Recording.create!(recordable: recordable, parent_recording: parent_recording)
          end

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
            client_id: api_client.id,
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
            client_id: api_client.id,
            key: key,
            payload: result.fetch(:json),
            status: result.fetch(:status, :created).to_s
          )
        end

        def assert_parent_allowed!(parent_recording)
          RecordingStudio.assert_parent_allowed!(child_type: recordable_type, parent_recording: parent_recording)
        end

        def invalid_parent_input_error(message)
          RecordingStudioApi::InvalidActionInputError.new(
            message,
            details: [
              {
                attribute: :parent_id,
                message: "is not allowed for #{recordable_type}",
                full_message: message,
                type: :invalid
              }
            ]
          )
        end
      end
    end
  end
end
