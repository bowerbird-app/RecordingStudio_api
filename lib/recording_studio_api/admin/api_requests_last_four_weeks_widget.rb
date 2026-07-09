# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    module ApiRequestsLastFourWeeksWidget
      WIDGET_KEY = "widgets.recording_studio_api.requests_last_four_weeks"

      Definition = ::RecordingStudioAdmin::Widget.new(
        nil,
        registry_prefix: WIDGET_KEY
      ) do
        type :chart
        title "API requests"
        description "API request volume for the last 4 weeks."
        value { |context| RecordingStudioApi::Admin::ApiRequestsLastFourWeeksWidget.total(context) }
        metadata { { period_label: "Last 4 weeks" } }
        hide_change
        chart_type :column
        series { |context| RecordingStudioApi::Admin::ApiRequestsLastFourWeeksWidget.series(context) }
        chart_options do
          {
            height: 240,
            plotOptions: { bar: { horizontal: false, columnWidth: "52%" } },
            xaxis: { labels: { rotate: 0, hideOverlappingLabels: true } },
            yaxis: { min: 0, forceNiceScale: true },
            dataLabels: { enabled: false },
            stroke: { width: 0 }
          }
        end
        link_to { |context| RecordingStudioApi::Admin::ApiRequestsLastFourWeeksWidget.link_to(context) }
        link_label "API requests"
      end

      module_function

      def series(context)
        [{
          name: "API requests",
          data: daily_points(context).map { |point| { x: point[:label], y: point[:count] } }
        }]
      end

      def total(context)
        return 0 unless RecordingStudioApi::ApiRequestLog.table_available?

        request_scope(context).where(occurred_at: time_range).count
      end

      def link_to(context)
        query = {
          start_date: start_date.iso8601,
          end_date: Date.current.iso8601,
          group_by: "day"
        }

        "#{context.admin_screen_path('api_requests')}?#{query.to_query}"
      end

      def daily_points(context)
        buckets = daily_buckets
        counts = buckets.index_with(0)

        if RecordingStudioApi::ApiRequestLog.table_available?
          request_scope(context).where(occurred_at: time_range).pluck(:occurred_at).each do |occurred_at|
            bucket = occurred_at.to_date
            counts[bucket] += 1 if counts.key?(bucket)
          end
        end

        buckets.map do |bucket|
          {
            label: bucket.strftime("%b %-d"),
            count: counts.fetch(bucket, 0)
          }
        end
      end

      def request_scope(context)
        RecordingStudioApi::Admin::ApiAccessRequestsScreen.request_scope(context)
      end

      def daily_buckets
        27.downto(0).map { |days_ago| Date.current - days_ago.days }
      end

      def time_range
        start_date.beginning_of_day..Time.current
      end

      def start_date
        daily_buckets.first
      end
    end
  end
end