# frozen_string_literal: true

module RecordingStudioApi
  module Services
    module ResourceOperations
      class Destroy < Base
        def call
          authorize_access!(recording, role: :edit, include_trashed: true)

          serialized_recording = serialize_recording(recording)
          destroy_resource!(recording)

          { json: serialize_delete_result(serialized_recording, deleted_via: "destroyed") }
        end
      end
    end
  end
end