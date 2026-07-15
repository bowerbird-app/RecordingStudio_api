# frozen_string_literal: true

module RecordingStudioApi
  module Services
    module ResourceOperations
      class Show < Base
        def call
          authorize_access!(recording, role: :view)

          { json: { data: serialize_recording(recording) } }
        end
      end
    end
  end
end