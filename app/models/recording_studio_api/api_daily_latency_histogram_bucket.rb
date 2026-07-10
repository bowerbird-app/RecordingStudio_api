# frozen_string_literal: true

module RecordingStudioApi
  class ApiDailyLatencyHistogramBucket < LogRecord
    self.table_name = "recording_studio_api_api_daily_latency_histogram_buckets"
  end
end