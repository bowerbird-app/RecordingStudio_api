# frozen_string_literal: true

module RecordingStudioApi
  module Services
    module ResourceOperations
      class Update < Base
        def call
          authorize_access!(recording, role: :edit)

          attributes = resource_attributes
          recording.recordable.update!(attributes) if attributes.any?

          { json: { data: serialize_recording(recording.reload) } }
        end
      end
    end
  end
end