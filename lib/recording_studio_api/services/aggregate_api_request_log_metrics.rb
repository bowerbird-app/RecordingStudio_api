# frozen_string_literal: true

module RecordingStudioApi
  module Services
    class AggregateApiRequestLogMetrics
      LATENCY_BUCKETS_MS = [25, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000, 30_000].freeze

      class << self
        def call(metric_date: Date.yesterday)
          new(metric_date: metric_date).call
        end
      end

      def initialize(metric_date:)
        @metric_date = metric_date.to_date
      end

      def call
        return false unless tables_available?

        ApiDailyMetric.transaction do
          delete_existing_metrics!
          persist_daily_metrics!
          persist_histogram_buckets!
        end
        true
      end

      private

      attr_reader :metric_date

      def tables_available?
        ApiRequestLog.table_available? && ApiDailyMetric.table_available? && ApiDailyLatencyHistogramBucket.table_available?
      end

      def log_rows
        @log_rows ||= ApiRequestLog.where(occurred_at: metric_date.beginning_of_day..metric_date.end_of_day)
                                   .pluck(:api_key, :route_name, :controller_name, :action_name, :request_method, :status_code, :rate_limited, :duration_ms)
      end

      def delete_existing_metrics!
        ApiDailyMetric.where(metric_date: metric_date).delete_all
        ApiDailyLatencyHistogramBucket.where(metric_date: metric_date).delete_all
      end

      def persist_daily_metrics!
        grouped_rows.each do |(api_key, route_name, request_method, status_class), rows|
          durations = rows.map { |row| row[7] }.compact
          ApiDailyMetric.create!(
            api_key: api_key,
            metric_date: metric_date,
            route_name: route_name,
            controller_name: rows.first[2],
            action_name: rows.first[3],
            request_method: request_method,
            status_class: status_class,
            request_count: rows.size,
            rate_limited_count: rows.count { |row| row[6] || row[5].to_i == 429 },
            client_error_count: rows.count { |row| (400..499).cover?(row[5].to_i) },
            server_error_count: rows.count { |row| (500..599).cover?(row[5].to_i) },
            duration_count: durations.size,
            duration_sum_ms: durations.sum,
            duration_max_ms: durations.max.to_i
          )
        end
      end

      def persist_histogram_buckets!
        grouped_rows.each do |(api_key, route_name, request_method, status_class), rows|
          rows.map { |row| row[7] }.compact.group_by { |duration| latency_bucket_for(duration) }.each do |upper_bound_ms, durations|
            ApiDailyLatencyHistogramBucket.create!(
              api_key: api_key,
              metric_date: metric_date,
              route_name: route_name,
              request_method: request_method,
              status_class: status_class,
              upper_bound_ms: upper_bound_ms,
              request_count: durations.size
            )
          end
        end
      end

      def grouped_rows
        @grouped_rows ||= log_rows.group_by do |api_key, route_name, _controller_name, _action_name, request_method, status_code, *_|
          [api_key.presence || "public", route_name.presence || "unknown", request_method, status_code.to_i / 100]
        end
      end

      def latency_bucket_for(duration)
        LATENCY_BUCKETS_MS.find { |upper_bound| duration <= upper_bound } || LATENCY_BUCKETS_MS.last
      end
    end
  end
end