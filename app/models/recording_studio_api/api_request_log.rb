# frozen_string_literal: true

module RecordingStudioApi
  class ApiRequestLog < LogRecord
    self.table_name = "recording_studio_api_api_request_logs"

    def api_client_name
      return if api_client_id.blank?

      RecordingStudioApi::ApiClient.where(id: api_client_id).pick(:name)
    end
  end
end
