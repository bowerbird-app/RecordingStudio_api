# frozen_string_literal: true

module RecordingStudioApi
  class ApiRequestLog < LogRecord
    self.table_name = "recording_studio_api_api_request_logs"
  end
end
