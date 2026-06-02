# frozen_string_literal: true

module RecordingStudioApi
  module Services
    module ResourceOperations
      class Update < Base
        def call
          authorize_access!(recording, role: :edit)

          recording.recordable.update!(resource_attributes)

          { json: { data: serialize_recording(recording.reload) } }
        end
      end
    end
  end
end