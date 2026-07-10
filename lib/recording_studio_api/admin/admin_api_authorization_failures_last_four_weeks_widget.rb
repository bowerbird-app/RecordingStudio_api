# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    module AdminApiAuthorizationFailuresLastFourWeeksWidget
      WIDGET_KEY = "widgets.recording_studio_api.admin.authorization_failures_last_four_weeks"
      STATUS_CODES = {
        "Unauthenticated (401)" => 401,
        "Forbidden (403)" => 403
      }.freeze

      Definition = ::RecordingStudioAdmin::Widget.new(
        nil,
        registry_prefix: WIDGET_KEY
      ) do
        type :chart
        title "Authorization failures"
        description "Site-wide unauthenticated and forbidden API requests for the last 4 weeks."
        change_good_when :down
        value { |context| RecordingStudioApi::Admin::AdminApiAuthorizationFailuresLastFourWeeksWidget.total(context) }
        metadata { { period_label: "Last 4 weeks" } }
        change { |context|
          current = RecordingStudioApi::Admin::AdminApiAuthorizationFailuresLastFourWeeksWidget.total(context)
          previous = RecordingStudioApi::Admin::AdminApiAuthorizationFailuresLastFourWeeksWidget.previous_total(context)
          RecordingStudioApi::Admin::ApiAccessRequestsScreen.format_change(
            RecordingStudioApi::Admin::ApiAccessRequestsScreen.percent_change(current, previous)
          )
        }
        chart_type :area
        series { RecordingStudioApi::Admin::AdminApiAuthorizationFailuresLastFourWeeksWidget.series }
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
        link_to { |context| RecordingStudioApi::Admin::AdminApiAuthorizationFailuresLastFourWeeksWidget.link_to(context) }
        link_label "Authorization failures"
      end

      module_function

      def series
        STATUS_CODES.map do |label, status_code|
          {
            name: label,
            data: daily_points_for(status_code).map { |point| { x: point[:label], y: point[:count] } }
          }
        end
      end

      def total(_context = nil)
        request_scope.where(occurred_at: time_range).count
      end

      def previous_total(_context = nil)
        request_scope.where(occurred_at: previous_time_range).count
      end

      def link_to(context)
        query = {
          start_date: daily_buckets.first.iso8601,
          end_date: Date.current.iso8601,
          group_by: "day",
          status: "authorization_failure"
        }

        "#{context.admin_screen_path('admin_api_requests')}?#{query.to_query}"
      end

      def request_scope
        return RecordingStudioApi::ApiRequestLog.none unless RecordingStudioApi::ApiRequestLog.table_available?

        RecordingStudioApi::ApiRequestLog.where(status_code: STATUS_CODES.values)
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

      def daily_points_for(status_code)
        buckets = daily_buckets
        counts = buckets.index_with(0)

        request_scope.where(status_code:, occurred_at: time_range).pluck(:occurred_at).each do |occurred_at|
          next if occurred_at.nil?

          day = occurred_at.in_time_zone.to_date
          counts[day] += 1 if counts.key?(day)
        end

        buckets.map { |bucket| { label: bucket.strftime("%b %-d"), count: counts.fetch(bucket, 0) } }
      end
    end
  end
end