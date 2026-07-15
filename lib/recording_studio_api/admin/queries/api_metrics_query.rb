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
          def call(start_date:, end_date:, status_class: nil, rate_limited: nil)
            new(start_date:, end_date:, status_class:, rate_limited:).call
          end
        end

        def initialize(start_date:, end_date:, status_class:, rate_limited:)
          @start_date = start_date.to_date
          @end_date = end_date.to_date
          @status_class = status_class
          @rate_limited = rate_limited
        end

        def call
          rows = aggregate_rows + raw_rows
          rows.group_by { |row| [row.metric_date, row.route_name, row.request_method, row.status_class] }
              .map { |_key, grouped_rows| merge(grouped_rows) }
        end

        private

        attr_reader :start_date, :end_date, :status_class, :rate_limited

        def aggregate_rows
          return [] unless ApiDailyMetric.table_available?

          scope = ApiDailyMetric.where(metric_date: start_date..aggregate_end_date)
          scope = scope.where(status_class: status_class) if status_class
          scope = scope.where("rate_limited_count > 0") if rate_limited == true
          scope.map { |metric| row_from_metric(metric) }
        end

        def raw_rows
          return [] unless ApiRequestLog.table_available?

          scope = ApiRequestLog.where(occurred_at: raw_start_date.beginning_of_day..end_date.end_of_day)
          scope = scope.where(status_code: (status_class.to_i * 100)..((status_class.to_i * 100) + 99)) if status_class
          scope = scope.where(rate_limited: true) if rate_limited == true
          scope.pluck(:occurred_at, :route_name, :request_method, :status_code, :rate_limited, :duration_ms)
               .map { |values| row_from_log(*values) }
        end

        def aggregate_end_date
          [end_date, raw_cutoff_date - 1.day].min
        end

        def raw_start_date
          [start_date, raw_cutoff_date].max
        end

        def raw_cutoff_date
          retention_days = RecordingStudioApi.configuration.api_request_log_retention_days
          return Date.new(0) if retention_days.nil?

          (Time.current - retention_days.to_i.days).to_date
        end

        def row_from_metric(metric)
          Row.new(**metric.attributes.symbolize_keys.slice(*Row.members))
        end

        def row_from_log(occurred_at, route_name, request_method, status_code, rate_limited, duration_ms)
          status = status_code.to_i
          Row.new(
            metric_date: occurred_at.to_date,
            route_name: route_name.presence || "unknown",
            request_method: request_method,
            status_class: status / 100,
            request_count: 1,
            rate_limited_count: rate_limited || status == 429 ? 1 : 0,
            client_error_count: (400..499).cover?(status) ? 1 : 0,
            server_error_count: (500..599).cover?(status) ? 1 : 0,
            duration_count: duration_ms.present? ? 1 : 0,
            duration_sum_ms: duration_ms.to_i,
            duration_max_ms: duration_ms.to_i
          )
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