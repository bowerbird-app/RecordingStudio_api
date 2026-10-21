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

      SeriesContext = Struct.new(:params, keyword_init: true) do
        def filter_value(_key)
          nil
        end
      end

      key "admin_api_performance"
      icon :bolt
      title "API performance"
      subtitle "Site-wide API latency and slow endpoint analysis."

      query do |context|
        RecordingStudioApi::Admin::AdminApiPerformanceScreen.endpoint_rows(context)
      end

      filter :date_range, default: :last_4_weeks
      filter :group_by, values: %i[hour day week month year], default: :day
      filter :request_method, values: %w[GET POST PUT PATCH DELETE], placeholder: "Method", apply: lambda { |rows, value, _context|
        if value.present?
          rows.select { |row| row.request_method.to_s == value.to_s }
        else
          rows
        end
      }
      filter :request_path, placeholder: "Request path", apply: lambda { |rows, value, _context|
        if value.present?
          rows.select { |row| row.request_path.to_s == value.to_s }
        else
          rows
        end
      }
      filter_presentation :inline

      summary do
        label "Endpoints"
        change_good_when :neutral
      end

      chart do
        title "Latency over time"
        type :area
        series lambda { |context|
          RecordingStudioApi::Admin::AdminApiPerformanceScreen.latency_series_for(context)
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
          return [] unless authorized?(context)

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

        def latency_series_for(context)
          return [] unless RecordingStudioApi::ApiRequestLog.table_available?

          bucket = group_by_from_context(context)
          buckets = chart_buckets(context, bucket)
          return [] if buckets.empty?

          durations_by_bucket = scoped_raw_durations(context, buckets, bucket)

          [
            {
              name: "P95 duration",
              data: buckets.map do |bucket_start|
                {
                  x: RecordingStudioApi::Admin::ApiAccessRequestsScreen.chart_bucket_label(bucket_start, bucket),
                  y: series_point(durations_by_bucket, bucket_start, 0.95)
                }
              end
            },
            {
              name: "Average duration",
              data: buckets.map do |bucket_start|
                {
                  x: RecordingStudioApi::Admin::ApiAccessRequestsScreen.chart_bucket_label(bucket_start, bucket),
                  y: series_point(durations_by_bucket, bucket_start, :average)
                }
              end
            }
          ]
        end

        def scoped_raw_durations(context, buckets, bucket)
          durations_by_bucket = buckets.index_with { [] }
          request_scope(context).pluck(:occurred_at, :duration_ms).each do |occurred_at, duration_ms|
            next if occurred_at.nil? || duration_ms.nil?

            bucket_start = RecordingStudioApi::Admin::ApiAccessRequestsScreen.chart_bucket_start(occurred_at, bucket)
            durations_by_bucket[bucket_start] << duration_ms if durations_by_bucket.key?(bucket_start)
          end
          durations_by_bucket
        end

        def series_point(durations_by_bucket, bucket, kind)
          return unless durations_by_bucket.key?(bucket)

          values = durations_by_bucket.fetch(bucket)
          kind == :average ? average(values) : percentile(values, kind)
        end

        def request_scope(context)
          start_date, end_date = date_range_from_context(context)
          scope = RecordingStudioApi::ApiRequestLog.where(
            api_key: RecordingStudioApi::Admin::ApiContext.key_from_context(context),
            occurred_at: start_date.beginning_of_day..end_date.end_of_day
          )
          apply_request_log_filters(
            scope,
            request_method: request_filter_value(context, :request_method),
            request_path: request_filter_value(context, :request_path)
          )
        end

        def request_filter_value(context, key)
          value = context.filter_value(key) if context.respond_to?(:filter_value)
          return value if value.present?

          context.params[key] || context.params[key.to_s]
        end

        def group_by_from_context(context)
          value = request_filter_value(context, :group_by)
          (value.presence || :day).to_sym
        end

        def apply_request_log_filters(scope, request_method:, request_path:)
          scope = scope.where(request_method: request_method) if request_method.present?
          scope = scope.where(request_path: request_path) if request_path.present?
          scope
        end

        def authorized?(context)
          RecordingStudioApi::Admin::ApiAuthorization.authorized?(
            actor: context.current_actor,
            api: RecordingStudioApi::Admin::ApiContext.key_from_context(context),
            root_recording: context.root_recording,
            role: RecordingStudioApi.configuration.access_management_view_role
          )
        end

        def date_range_from_context(context)
          filter_value = context.filter_value(:date_range) if context.respond_to?(:filter_value)
          start_date = filter_value&.start_date ||
                       parsed_date(context.params[:start_date] || context.params["start_date"]) ||
                       default_start_date
          end_date = filter_value&.end_date ||
                     parsed_date(context.params[:end_date] || context.params["end_date"]) ||
                     Date.current
          start_date > end_date ? [end_date, start_date] : [start_date, end_date]
        end

        def default_start_date
          Date.current - 27.days
        end

        def chart_buckets(context, bucket)
          start_date, end_date = date_range_from_context(context)
          helper = RecordingStudioApi::Admin::ApiAccessRequestsScreen
          start_bucket = helper.chart_range_start(start_date, bucket)
          end_bucket = helper.chart_range_end(end_date, bucket)
          buckets = []
          current_bucket = start_bucket

          while current_bucket <= end_bucket
            buckets << current_bucket
            current_bucket = helper.next_chart_bucket(current_bucket, bucket)
          end

          buckets
        end

        def series_context(start_date:, end_date:, api: :public, request_method: nil, request_path: nil, group_by: :day)
          AdminApiPerformanceScreen::SeriesContext.new(
            params: {
              start_date: start_date.to_date.iso8601,
              end_date: end_date.to_date.iso8601,
              api_key: RecordingStudioApi::Admin::ApiContext.resolve(api).name,
              request_method: request_method,
              request_path: request_path,
              group_by: group_by
            }.compact
          )
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