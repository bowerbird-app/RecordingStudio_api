# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    module Queries
      class ApiMetricsQuery
        Row = Struct.new(
          :metric_date, :route_name, :request_method, :status_class, :request_count,
          :rate_limited_count, :client_error_count, :server_error_count,
          :duration_count, :duration_sum_ms, :duration_max_ms,
          keyword_init: true
        )

        class << self
          def call(start_date:, end_date:, status_class: nil, rate_limited: nil, api: :public)
            new(start_date:, end_date:, status_class:, rate_limited:, api: api).call
          end
        end

        def initialize(start_date:, end_date:, status_class:, rate_limited:, api:)
          @start_date = start_date.to_date
          @end_date = end_date.to_date
          @status_class = status_class
          @rate_limited = rate_limited
          @api_key = RecordingStudioApi::Admin::ApiContext.resolve(api).name
        end

        def call
          rows = LogsRegistration.summaries_enabled? ? coverage_rows : (aggregate_rows + raw_rows)
          rows.group_by { |row| [row.metric_date, row.route_name, row.request_method, row.status_class] }
              .map { |_key, grouped_rows| merge(grouped_rows) }
        end

        private

        attr_reader :start_date, :end_date, :status_class, :rate_limited, :api_key

        def coverage_rows
          coverage = Services::ApiRequestLogCoverage.new
          (start_date..end_date).flat_map do |day|
            case coverage.source_for(day).kind
            when :summary then summary_rows_for(day)
            when :raw then raw_rows_for_day(day)
            when :legacy then legacy_rows_for(day)
            else []
            end
          end
        end

        def summary_rows_for(day)
          return [] unless ApiRequestDaySummary.table_available?

          connection = ApiRequestDaySummary.connection
          binds = [api_key, day]
          sql = <<~SQL.squish
            SELECT
              route_name,
              request_method,
              (status_code / 100) AS status_class,
              SUM(request_count) AS request_count,
              SUM(CASE WHEN rate_limited OR status_code = 429 THEN request_count ELSE 0 END) AS rate_limited_count,
              SUM(CASE WHEN status_code BETWEEN 400 AND 499 THEN request_count ELSE 0 END) AS client_error_count,
              SUM(CASE WHEN status_code BETWEEN 500 AND 599 THEN request_count ELSE 0 END) AS server_error_count,
              SUM(request_count) AS duration_count,
              SUM(duration_sum_ms) AS duration_sum_ms,
              MAX(duration_max_ms) AS duration_max_ms
            FROM #{ApiRequestDaySummary.table_name}
            WHERE api_key = ? AND day = ?
          SQL
          if status_class
            sql = "#{sql} AND status_code BETWEEN ? AND ?"
            range = status_class_range
            binds << range.begin
            binds << range.end
          end
          sql = "#{sql} AND (rate_limited = TRUE OR status_code = 429)" if rate_limited == true
          sql = "#{sql} GROUP BY 1, 2, 3"

          connection.select_all(ApiRequestLog.sanitize_sql_array([sql, *binds])).map do |values|
            Row.new(
              metric_date: day,
              route_name: values.fetch("route_name"),
              request_method: values.fetch("request_method"),
              status_class: values.fetch("status_class").to_i,
              request_count: values.fetch("request_count").to_i,
              rate_limited_count: values.fetch("rate_limited_count").to_i,
              client_error_count: values.fetch("client_error_count").to_i,
              server_error_count: values.fetch("server_error_count").to_i,
              duration_count: values.fetch("duration_count").to_i,
              duration_sum_ms: values.fetch("duration_sum_ms").to_i,
              duration_max_ms: values.fetch("duration_max_ms").to_i
            )
          end
        end

        def legacy_rows_for(day)
          return [] unless ApiDailyMetric.table_available?

          scope = ApiDailyMetric.where(api_key: api_key, metric_date: day)
          scope = scope.where(status_class: status_class) if status_class
          scope = scope.where("rate_limited_count > 0") if rate_limited == true
          scope.map { |metric| row_from_metric(metric) }
        end

        def raw_rows_for_day(day)
          start_at, finish_at = utc_window(day)
          raw_window_rows(start_at, finish_at, day)
        end

        def utc_window(day)
          start_at = Time.utc(day.year, day.month, day.day)
          [start_at, start_at + 1.day]
        end

        def status_class_range
          first = status_class.to_i * 100
          first..(first + 99)
        end

        def aggregate_rows
          return [] unless ApiDailyMetric.table_available?

          scope = ApiDailyMetric.where(api_key: api_key, metric_date: start_date..aggregate_end_date)
          scope = scope.where(status_class: status_class) if status_class
          scope = scope.where("rate_limited_count > 0") if rate_limited == true
          scope.map { |metric| row_from_metric(metric) }
        end

        def raw_rows
          return [] unless ApiRequestLog.table_available?
          return [] if raw_start_date > end_date

          start_at = raw_start_date.beginning_of_day
          finish_at = end_date.end_of_day
          select_raw_rows("DATE(occurred_at)", "occurred_at BETWEEN ? AND ?", [api_key, start_at, finish_at])
        end

        def raw_window_rows(start_at, finish_at, forced_date)
          select_raw_rows("?", "occurred_at >= ? AND occurred_at < ?", [forced_date, api_key, start_at, finish_at])
        end

        def select_raw_rows(date_sql, occurred_clause, binds)
          return [] unless ApiRequestLog.table_available?

          connection = ApiRequestLog.connection
          sql = <<~SQL.squish
            SELECT
              #{date_sql} AS metric_date,
              COALESCE(NULLIF(route_name, ''), 'unknown') AS route_name,
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
            WHERE api_key = ?
              AND #{occurred_clause}
          SQL

          if status_class
            sql = "#{sql} AND status_code BETWEEN ? AND ?"
            binds << (status_class.to_i * 100)
            binds << ((status_class.to_i * 100) + 99)
          end

          sql = "#{sql} AND (rate_limited = TRUE OR status_code = 429)" if rate_limited == true

          sql = <<~SQL.squish
            #{sql}
            GROUP BY 1, 2, 3, 4
          SQL

          connection.select_all(ApiRequestLog.sanitize_sql_array([sql, *binds])).map do |values|
            Row.new(
              metric_date: values.fetch("metric_date").to_date,
              route_name: values.fetch("route_name"),
              request_method: values.fetch("request_method"),
              status_class: values.fetch("status_class").to_i,
              request_count: values.fetch("request_count").to_i,
              rate_limited_count: values.fetch("rate_limited_count").to_i,
              client_error_count: values.fetch("client_error_count").to_i,
              server_error_count: values.fetch("server_error_count").to_i,
              duration_count: values.fetch("duration_count").to_i,
              duration_sum_ms: values.fetch("duration_sum_ms").to_i,
              duration_max_ms: values.fetch("duration_max_ms").to_i
            )
          end
        end

        def aggregate_end_date
          [end_date, raw_cutoff_date - 1.day].min
        end

        def raw_start_date
          [start_date, raw_cutoff_date].max
        end

        def raw_cutoff_date
          retention_days = RecordingStudioApi::ApiRuntimePolicy.for(:public).api_request_log_retention_days
          return Date.new(0) if retention_days.nil?

          (Time.current - retention_days.to_i.days).to_date
        end

        def row_from_metric(metric)
          Row.new(**metric.attributes.symbolize_keys.slice(*Row.members))
        end

        def merge(rows)
          first = rows.first
          Row.new(
            metric_date: first.metric_date,
            route_name: first.route_name,
            request_method: first.request_method,
            status_class: first.status_class,
            request_count: rows.sum(&:request_count),
            rate_limited_count: rows.sum(&:rate_limited_count),
            client_error_count: rows.sum(&:client_error_count),
            server_error_count: rows.sum(&:server_error_count),
            duration_count: rows.sum(&:duration_count),
            duration_sum_ms: rows.sum(&:duration_sum_ms),
            duration_max_ms: rows.map(&:duration_max_ms).max
          )
        end
      end
    end
  end
end
