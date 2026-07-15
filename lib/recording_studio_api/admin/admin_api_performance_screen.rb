# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    class AdminApiPerformanceScreen < ::RecordingStudioAdmin::Screen
      Row = Struct.new(
        :request_method,
        :request_path,
        :request_count,
        :average_duration_ms,
        :p50_duration_ms,
        :p95_duration_ms,
        :max_duration_ms,
        :server_error_count,
        :client_error_count,
        :rate_limited_count,
        keyword_init: true
      )

      key "admin_api_performance"
      icon :bolt
      title "API performance"
      subtitle "Site-wide API latency and slow endpoint analysis."

      query do |context|
        RecordingStudioApi::Admin::AdminApiPerformanceScreen.endpoint_rows(context)
      end

      summary do
        label "Endpoints"
        change_good_when :neutral
      end

      chart do
        title "Latency over time"
        type :area
        series lambda { |context|
          start_date, end_date = RecordingStudioApi::Admin::AdminApiPerformanceScreen.date_range_from_context(context)
          RecordingStudioApi::Admin::AdminApiPerformanceScreen.latency_series_for(start_date, end_date)
        }
        options lambda { |_context|
          {
            xaxis: { labels: { rotate: -45, hideOverlappingLabels: true } },
            yaxis: { min: 0, forceNiceScale: true },
            stroke: { curve: "smooth", width: 2 },
            dataLabels: { enabled: false },
            fill: { opacity: 0.18 }
          }
        }
      end

      table do
        filter :search, apply: lambda { |rows, value, _context|
          next rows if value.blank?

          query = value.to_s.downcase
          rows.select do |row|
            [row.request_method, row.request_path].any? { |entry| entry.to_s.downcase.include?(query) }
          end
        }

        column :request_method, title: "Method", sortable: false
        column :request_path,
               title: "Path",
               sortable: false,
               value: ->(row, _context) { RecordingStudioApi::Admin::ApiRequestLogHelpers.compact_path(row.request_path) },
               tooltip: ->(row, _context) { row.request_path }
        column :request_count, title: "Requests", sortable: false
        column :average_duration_ms, title: "Avg duration", sortable: false
        column :p50_duration_ms, title: "P50 duration", sortable: false
        column :p95_duration_ms, title: "P95 duration", sortable: false
        column :max_duration_ms, title: "Max duration", sortable: false
        column :server_error_count, title: "Server errors", sortable: false
        column :client_error_count, title: "Client errors", sortable: false
        column :rate_limited_count, title: "Rate limited", sortable: false
        default_columns :request_method, :request_path, :request_count, :average_duration_ms, :p50_duration_ms, :p95_duration_ms, :max_duration_ms
        paginate per_page: 25, mode: :infinite
      end

      class << self
        def endpoint_rows(context)
          return [] unless RecordingStudioApi::ApiRequestLog.table_available?

          logs = request_scope(context).pluck(:request_method, :request_path, :duration_ms, :status_code, :rate_limited)
          grouped = logs.group_by { |request_method, request_path, *_| [request_method, request_path] }

          rows = grouped.map do |(request_method, request_path), rows|
            durations = rows.map { |row| row[2] }.compact
            Row.new(
              request_method: request_method,
              request_path: request_path,
              request_count: rows.size,
              average_duration_ms: average(durations),
              p50_duration_ms: percentile(durations, 0.50),
              p95_duration_ms: percentile(durations, 0.95),
              max_duration_ms: durations.max.to_i,
              server_error_count: rows.count { |row| (500..599).cover?(row[3].to_i) },
              client_error_count: rows.count { |row| (400..499).cover?(row[3].to_i) },
              rate_limited_count: rows.count { |row| row[4] }
            )
          end

          rows.sort_by { |row| [-row.p95_duration_ms.to_i, -row.average_duration_ms.to_i, row.request_path.to_s] }
        end

        def latency_series_for(start_date, end_date)
          return [] unless RecordingStudioApi::ApiRequestLog.table_available?

          buckets = daily_buckets(start_date, end_date)
          durations_by_bucket = buckets.index_with { [] }

          RecordingStudioApi::ApiRequestLog
            .where(occurred_at: start_date.beginning_of_day..end_date.end_of_day)
            .pluck(:occurred_at, :duration_ms)
            .each do |occurred_at, duration_ms|
              next if occurred_at.nil? || duration_ms.nil?

              bucket = occurred_at.to_date
              durations_by_bucket[bucket] << duration_ms if durations_by_bucket.key?(bucket)
            end

          [
            {
              name: "P95 duration",
              data: buckets.map { |bucket| { x: bucket.strftime("%b %-d"), y: percentile(durations_by_bucket.fetch(bucket), 0.95) } }
            },
            {
              name: "Average duration",
              data: buckets.map { |bucket| { x: bucket.strftime("%b %-d"), y: average(durations_by_bucket.fetch(bucket)) } }
            }
          ]
        end

        def request_scope(context)
          start_date, end_date = date_range_from_context(context)
          RecordingStudioApi::ApiRequestLog.where(occurred_at: start_date.beginning_of_day..end_date.end_of_day)
        end

        def date_range_from_context(context)
          start_date = parsed_date(context.params[:start_date] || context.params["start_date"]) || default_start_date
          end_date = parsed_date(context.params[:end_date] || context.params["end_date"]) || Date.current
          start_date > end_date ? [end_date, start_date] : [start_date, end_date]
        end

        def default_start_date
          Date.current - 27.days
        end

        def daily_buckets(start_date, end_date)
          buckets = []
          current_date = start_date.to_date

          while current_date <= end_date.to_date
            buckets << current_date
            current_date += 1.day
          end

          buckets
        end

        def average(values)
          return 0 if values.empty?

          (values.sum / values.size.to_f).round
        end

        def percentile(values, percentile_value)
          return 0 if values.empty?

          sorted_values = values.sort
          rank = (percentile_value * (sorted_values.size - 1)).ceil
          sorted_values.fetch(rank).to_i
        end

        def parsed_date(raw_date)
          return if raw_date.blank?

          Date.iso8601(raw_date.to_s)
        rescue ArgumentError
          nil
        end
      end
    end
  end
end