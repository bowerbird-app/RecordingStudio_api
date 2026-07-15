# frozen_string_literal: true

module RecordingStudioApi
  module Services
    module ResourceOperations
      class Create < Base
        def call
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

          {
            json: { data: serialize_recording(created_recording) },
            status: :created
          }
        rescue RecordingStudio::InvalidParent => e
          raise invalid_parent_input_error(e.message)
        end

        private

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