# frozen_string_literal: true

module RecordingStudioApi
  module Services
    module ResourceOperations
      class Create < Base
        def call
          recordable_class = recordable_type.safe_constantize
          raise RecordingStudioApi::NotFoundError, "Unknown API resource #{resource_name}" if recordable_class.nil?

          recordable = recordable_class.create!(resource_attributes)
          created_recording = RecordingStudio::Recording.create!(recordable: recordable, parent_recording: parent_recording_for_create)

          {
            json: { data: serialize_recording(created_recording) },
            status: :created
          }
        end
      end
    end
  end
end