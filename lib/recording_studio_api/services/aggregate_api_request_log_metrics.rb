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

      def delete_existing_metrics!
        ApiDailyMetric.where(metric_date: metric_date).delete_all
        ApiDailyLatencyHistogramBucket.where(metric_date: metric_date).delete_all
      end

      def persist_daily_metrics!
        connection = ApiRequestLog.connection
        sql = <<~SQL.squish
          SELECT
            COALESCE(NULLIF(api_key, ''), 'public') AS api_key,
            COALESCE(NULLIF(route_name, ''), 'unknown') AS route_name,
            MIN(controller_name) AS controller_name,
            MIN(action_name) AS action_name,
            request_method,
            (status_code / 100) AS status_class,
            COUNT(*) AS request_count,
            SUM(CASE WHEN rate_limited OR status_code = 429 THEN 1 ELSE 0 END) AS rate_limited_count,
            SUM(CASE WHEN status_code BETWEEN 400 AND 499 THEN 1 ELSE 0 END) AS client_error_count,
            SUM(CASE WHEN status_code BETWEEN 500 AND 599 THEN 1 ELSE 0 END) AS server_error_count,
            COUNT(duration_ms) AS duration_count,
            COALESCE(SUM(duration_ms), 0) AS duration_sum_ms,
            COALESCE(MAX(duration_ms), 0) AS duration_max_ms
          FROM #{ApiRequestLog.table_name}
          WHERE occurred_at BETWEEN ? AND ?
          GROUP BY 1, 2, 5, 6
        SQL

        connection.select_all(
          ApiRequestLog.sanitize_sql_array([sql, metric_date.beginning_of_day, metric_date.end_of_day])
        ).each do |row|
          ApiDailyMetric.create!(
            api_key: row.fetch("api_key"),
            metric_date: metric_date,
            route_name: row.fetch("route_name"),
            controller_name: row["controller_name"],
            action_name: row["action_name"],
            request_method: row.fetch("request_method"),
            status_class: row.fetch("status_class").to_i,
            request_count: row.fetch("request_count").to_i,
            rate_limited_count: row.fetch("rate_limited_count").to_i,
            client_error_count: row.fetch("client_error_count").to_i,
            server_error_count: row.fetch("server_error_count").to_i,
            duration_count: row.fetch("duration_count").to_i,
            duration_sum_ms: row.fetch("duration_sum_ms").to_i,
            duration_max_ms: row.fetch("duration_max_ms").to_i
          )
        end
      end

      def persist_histogram_buckets!
        connection = ApiRequestLog.connection
        bucket_case = LATENCY_BUCKETS_MS.map.with_index do |upper_bound, index|
          lower = index.zero? ? 0 : LATENCY_BUCKETS_MS[index - 1] + 1
          if index == LATENCY_BUCKETS_MS.length - 1
            "WHEN duration_ms >= #{lower} THEN #{upper_bound}"
          else
            "WHEN duration_ms BETWEEN #{lower} AND #{upper_bound} THEN #{upper_bound}"
          end
        end.join(" ")

        sql = <<~SQL.squish
          SELECT
            COALESCE(NULLIF(api_key, ''), 'public') AS api_key,
            COALESCE(NULLIF(route_name, ''), 'unknown') AS route_name,
            request_method,
            (status_code / 100) AS status_class,
            CASE #{bucket_case} END AS upper_bound_ms,
            COUNT(*) AS request_count
          FROM #{ApiRequestLog.table_name}
          WHERE occurred_at BETWEEN ? AND ?
            AND duration_ms IS NOT NULL
          GROUP BY 1, 2, 3, 4, 5
        SQL

        connection.select_all(
          ApiRequestLog.sanitize_sql_array([sql, metric_date.beginning_of_day, metric_date.end_of_day])
        ).each do |row|
          next if row["upper_bound_ms"].nil?

          ApiDailyLatencyHistogramBucket.create!(
            api_key: row.fetch("api_key"),
            metric_date: metric_date,
            route_name: row.fetch("route_name"),
            request_method: row.fetch("request_method"),
            status_class: row.fetch("status_class").to_i,
            upper_bound_ms: row.fetch("upper_bound_ms").to_i,
            request_count: row.fetch("request_count").to_i
          )
        end
      end
    end
  end
end
