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
      end
    end
  end
end
