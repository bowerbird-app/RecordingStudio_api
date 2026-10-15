# frozen_string_literal: true

module RecordingStudioApi
  module Services
    module ResourceMetrics
      class Index < ResourceOperations::Base
        def call
          assert_index_enabled!
          authorize_access!(access_scope_recording, role: :view)
          entries = RecordingStudioApi.metrics_for(recordable_type, api: api_key)
          { json: { metrics: entries.map(&:as_json) } }
        end

        private

        def assert_index_enabled!
          registration = RecordingStudioApi.recordable_registration_for(recordable_type, api: api_key)
          return if registration&.supports_operation?(:index)

          raise RecordingStudioApi::UnsupportedActionError, "index is not enabled for #{recordable_type}"
        end
      end
    end
  end
end
