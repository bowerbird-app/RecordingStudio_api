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
        retention: :indefinite
      )

      RecordingStudioLogs.finalize!
    end
  end
end
