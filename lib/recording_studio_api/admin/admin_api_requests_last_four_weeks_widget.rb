# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    module AdminApiRequestsLastFourWeeksWidget
      WIDGET_KEY = "widgets.recording_studio_api.admin.requests_last_four_weeks"

      Definition = ::RecordingStudioAdmin::Widget.new(
        nil,
        registry_prefix: WIDGET_KEY
      ) do
        type :chart
        title "API requests"
        description "Site-wide API request volume for the last 4 weeks."
        value { |context| RecordingStudioApi::Admin::AdminApiRequestsLastFourWeeksWidget.total(context) }
        metadata { { period_label: "Last 4 weeks" } }
        change do |context|
          current = RecordingStudioApi::Admin::AdminApiRequestsLastFourWeeksWidget.total(context)
          previous = RecordingStudioApi::Admin::AdminApiRequestsLastFourWeeksWidget.previous_total(context)
          RecordingStudioApi::Admin::ApiAccessRequestsScreen.format_change(
            RecordingStudioApi::Admin::ApiAccessRequestsScreen.percent_change(current, previous)
          )
        end
        chart_type :area
        series { RecordingStudioApi::Admin::AdminApiRequestsLastFourWeeksWidget.series }
        chart_options do
          {
            height: 240,
            xaxis: { labels: { rotate: 0, hideOverlappingLabels: true } },
            yaxis: { min: 0, forceNiceScale: true },
            dataLabels: { enabled: false },
            stroke: { curve: "smooth", width: 2 },
            fill: { opacity: 0.24 }
          }
        end
        link_to { |context| RecordingStudioApi::Admin::AdminApiRequestsLastFourWeeksWidget.link_to(context) }
        link_label "API requests"
      end

      module_function

      def series
        [{
          name: "API requests",
          data: daily_points.map { |point| { x: point[:label], y: point[:count] } }
        }]
      end

      def total(_context = nil)
        metric_total_for(time_range)
      end

      def link_to(context)
        query = {
          start_date: daily_buckets.first.iso8601,
          end_date: Date.current.iso8601,
          group_by: "day"
        }

        NavigationUrlHelpers.admin_screen_url(context, "admin_api_requests", query)
      end

      def daily_points
        buckets = daily_buckets
        counts = buckets.index_with(0)

        counts.merge!(RecordingStudioApi::Admin::ApiRequestLogHelpers.daily_metric_counts(start_date: buckets.first, end_date: buckets.last))

        buckets.map do |bucket|
          {
            label: bucket.strftime("%b %-d"),
            count: counts.fetch(bucket, 0)
          }
        end
      end

      def request_scope
        RecordingStudioApi::ApiRequestLog.all
      end

      def daily_buckets
        27.downto(0).map { |days_ago| Date.current - days_ago.days }
      end

      def time_range
        daily_buckets.first.beginning_of_day..Time.current
      end

      def previous_time_range
        period_days = daily_buckets.size
        previous_end = daily_buckets.first.beginning_of_day
        previous_start = previous_end - period_days.days
        previous_start.beginning_of_day...previous_end
      end

      def previous_total(_context = nil)
        metric_total_for(previous_time_range)
      end

      def metric_total_for(range)
        RecordingStudioApi::Admin::ApiRequestLogHelpers.metric_total(start_date: range.begin.to_date, end_date: range.end.to_date)
      end
    end
  end
end