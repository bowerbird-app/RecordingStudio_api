# frozen_string_literal: true

module RecordingStudioApi
  module Services
    module ResourceOperations
      class Show < Base
        def call
          authorize_access!(recording, role: :view)

          { json: serialize_recording(recording, context: relationship_context_for([recording])) }
        end
      end
    end
  end
end