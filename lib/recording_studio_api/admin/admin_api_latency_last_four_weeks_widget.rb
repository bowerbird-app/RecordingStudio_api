# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    module AdminApiLatencyLastFourWeeksWidget
      WIDGET_KEY = "widgets.recording_studio_api.admin.api_latency_last_four_weeks"

      Definition = ::RecordingStudioAdmin::Widget.new(
        nil,
        registry_prefix: WIDGET_KEY
      ) do
        type :chart
        title "API latency"
        description "Site-wide p95 API response time for the last 4 weeks."
        value { |context| "#{RecordingStudioApi::Admin::AdminApiLatencyLastFourWeeksWidget.p95_duration_ms(context)} ms" }
        metadata { { period_label: "Last 4 weeks" } }
        change_good_when :down
        change do |context|
          current = RecordingStudioApi::Admin::AdminApiLatencyLastFourWeeksWidget.p95_duration_ms(context)
          previous = RecordingStudioApi::Admin::AdminApiLatencyLastFourWeeksWidget.previous_p95_duration_ms(context)
          RecordingStudioApi::Admin::ApiAccessRequestsScreen.format_change(
            RecordingStudioApi::Admin::ApiAccessRequestsScreen.percent_change(current, previous)
          )
        end
        chart_type :area
        series { |context| RecordingStudioApi::Admin::AdminApiLatencyLastFourWeeksWidget.series(context) }
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
        link_to { |context| RecordingStudioApi::Admin::AdminApiLatencyLastFourWeeksWidget.link_to(context) }
        link_label "API performance"
      end

      module_function

      def series(context = nil)
        RecordingStudioApi::Admin::AdminApiPerformanceScreen.latency_series_for(
          RecordingStudioApi::Admin::AdminApiPerformanceScreen.default_start_date,
          Date.current,
          api: api_key(context)
        )
      end

      def p95_duration_ms(context = nil)
        p95_duration_ms_for(time_range, context)
      end

      def previous_p95_duration_ms(context = nil)
        p95_duration_ms_for(previous_time_range, context)
      end

      def p95_duration_ms_for(range, context = nil)
        return 0 unless RecordingStudioApi::ApiRequestLog.table_available?

        durations = request_scope(context).where(occurred_at: range).pluck(:duration_ms).compact
        RecordingStudioApi::Admin::AdminApiPerformanceScreen.percentile(durations, 0.95)
      end

      def link_to(context)
        query = {
          start_date: RecordingStudioApi::Admin::AdminApiPerformanceScreen.default_start_date.iso8601,
          end_date: Date.current.iso8601,
          group_by: "day"
        }

        NavigationUrlHelpers.admin_screen_url(context, "admin_api_performance", query)
      end

      def request_scope(context = nil)
        RecordingStudioApi::ApiRequestLog.where(api_key: api_key(context))
      end

      def api_key(context)
        context ? RecordingStudioApi::Admin::ApiContext.key_from_context(context) : "public"
      end

      def time_range
        RecordingStudioApi::Admin::AdminApiPerformanceScreen.default_start_date.beginning_of_day..Time.current
      end

      def previous_time_range
        current_range = time_range
        period_days = (current_range.begin.to_date..current_range.end.to_date).count
        previous_end = current_range.begin
        previous_start = previous_end - period_days.days
        previous_start...previous_end
      end
    end
  end
end