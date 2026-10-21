# frozen_string_literal: true

module RecordingStudioApi
  module LogsRegistration
    SOURCE_MODEL = "RecordingStudioApi::ApiRequestLog"
    OWNER = "RecordingStudioApi"

    module_function

    def register!
      return unless defined?(RecordingStudioLogs)

      RecordingStudioLogs.register(
        model: SOURCE_MODEL,
        timestamp_column: :occurred_at,
        partition_interval: nil,
        root_column: :root_recording_id,
        owner: OWNER,
        retention: :indefinite,
        aggregatable: {
          root_recording_id: { filter: [:eq], group: true },
          api_key: { filter: [:eq], group: true },
          route_name: { filter: [:eq], group: true },
          request_method: { filter: [:eq], group: true },
          status_code: { filter: [:eq], group: true },
          rate_limited: { filter: [:eq], group: true },
          latency_bucket_ms: { filter: [:eq], group: true },
          duration_ms: { measurements: %i[sum maximum] }
        }
      )

      RecordingStudioLogs.finalize!
    end
  end
end
