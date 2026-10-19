# frozen_string_literal: true

module RecordingStudioApi
  module Services
    class PruneApiDailyMetrics
      class << self
        def call(before: default_before)
          return 0 if before.nil?

          deleted = 0
          deleted += prune_daily_metrics!(before)
          deleted += prune_latency_buckets!(before)
          deleted += prune_log_summaries!(before) if LogsRegistration.summaries_enabled?
          deleted
        end

        private

        def default_before
          retention_days = RecordingStudioApi::ApiRuntimePolicy.for(:public).api_daily_metric_retention_days
          return if retention_days.nil?

          Date.current - retention_days.to_i.days
        end

        def prune_daily_metrics!(before)
          return 0 unless ApiDailyMetric.table_available?

          ApiDailyMetric.where("metric_date < ?", before).delete_all
        end

        def prune_latency_buckets!(before)
          return 0 unless ApiDailyLatencyHistogramBucket.table_available?

          ApiDailyLatencyHistogramBucket.where("metric_date < ?", before).delete_all
        end

        def prune_log_summaries!(before)
          deleted = 0
          deleted += ApiRequestDaySummary.where("day < ?", before).delete_all if ApiRequestDaySummary.table_available?
          deleted += ApiRequestLatencyDaySummary.where("day < ?", before).delete_all if ApiRequestLatencyDaySummary.table_available?
          invalidate_run_markers!(before)
          deleted
        end

        def invalidate_run_markers!(before)
          connection = LogsRegistration.logging_connection
          return unless connection.data_source_exists?("recording_studio_logs_aggregation_runs")

          names = [
            LogsRegistration::REQUEST_COUNTS,
            LogsRegistration::REQUEST_LATENCY
          ].map { |name| connection.quote(name) }.join(", ")
          sql = <<~SQL.squish
            DELETE FROM #{connection.quote_table_name('recording_studio_logs_aggregation_runs')}
            WHERE aggregation_name IN (#{names})
              AND day < #{connection.quote(before.to_date)}
          SQL
          connection.delete(sql)
        end
      end
    end
  end
end
