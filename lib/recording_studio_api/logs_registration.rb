# frozen_string_literal: true

module RecordingStudioApi
  module LogsRegistration
    SOURCE_MODEL = "RecordingStudioApi::ApiRequestLog"
    REQUEST_COUNTS = "api/request_counts"
    REQUEST_LATENCY = "api/request_latency"
    OWNER = "RecordingStudioApi"

    module_function

    def summaries_enabled?
      RecordingStudioApi.configuration.logs_summaries_enabled
    end

    def logging_connection
      ApiRequestLog.connection
    end

    def resolved_retention
      days = ApiRuntimePolicy.for(:public).api_request_log_retention_days
      return :indefinite if days.nil?

      days.to_i.days
    end

    def register!
      return unless defined?(RecordingStudioLogs)

      RecordingStudioLogs.register(
        model: SOURCE_MODEL,
        timestamp_column: :occurred_at,
        partition_interval: nil,
        root_column: :root_recording_id,
        owner: OWNER,
        retention: resolved_retention,
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

      RecordingStudioLogs.aggregate(
        source: SOURCE_MODEL,
        name: REQUEST_COUNTS,
        summary_model: "RecordingStudioApi::ApiRequestDaySummary",
        owner: OWNER,
        group_by: %i[root_recording_id api_key route_name request_method status_code rate_limited],
        measurements: {
          request_count: :count,
          duration_sum_ms: { sum: :duration_ms },
          duration_max_ms: { maximum: :duration_ms }
        }
      )

      RecordingStudioLogs.aggregate(
        source: SOURCE_MODEL,
        name: REQUEST_LATENCY,
        summary_model: "RecordingStudioApi::ApiRequestLatencyDaySummary",
        owner: OWNER,
        group_by: %i[root_recording_id api_key route_name request_method status_code latency_bucket_ms],
        measurements: {
          request_count: :count
        }
      )

      RecordingStudioLogs.finalize!
    end

    def request_counts_definition
      RecordingStudioLogs.registry.aggregation(REQUEST_COUNTS)
    end

    def request_latency_definition
      RecordingStudioLogs.registry.aggregation(REQUEST_LATENCY)
    end
  end
end
