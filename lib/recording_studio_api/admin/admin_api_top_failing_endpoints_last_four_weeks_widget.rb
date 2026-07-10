# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    module AdminApiTopFailingEndpointsLastFourWeeksWidget
      WIDGET_KEY = "widgets.recording_studio_api.admin.top_failing_endpoints_last_four_weeks"
      LIMIT = 5

      Definition = ::RecordingStudioAdmin::Widget.new(
        nil,
        registry_prefix: WIDGET_KEY
      ) do
        type :list
        title "Top failing endpoints"
        description "API endpoints with the most client and server errors over the last 4 weeks."
        metadata { { period_label: "Last 4 weeks" } }
        hide_metric
        hide_change
        list_options divider: true
        items { |context| RecordingStudioApi::Admin::AdminApiTopFailingEndpointsLastFourWeeksWidget.items(context) }
        link_to { |context| RecordingStudioApi::Admin::AdminApiTopFailingEndpointsLastFourWeeksWidget.link_to(context) }
        link_label "Failed requests"
      end

      module_function

      def items(context)
        rows = failing_endpoints
        return [{ text: "No failing endpoints", trailing: "Last 4 weeks" }] if rows.empty?

        rows.map do |row|
          {
            leading: request_method_badge(context, row[:request_method]),
            text: RecordingStudioApi::Admin::ApiRequestLogHelpers.compact_path(row[:request_path]),
            trailing: row[:error_count].to_s
          }
        end
      end

      def request_method_badge(context, request_method)
        context.view_context.render FlatPack::Badge::Component.new(
          text: request_method.to_s.upcase,
          style: request_method_badge_style(request_method),
          size: :sm
        )
      end

      def request_method_badge_style(request_method)
        case request_method.to_s.upcase
        when "GET" then :info
        when "POST" then :success
        when "PUT", "PATCH" then :warning
        when "DELETE" then :danger
        else :default
        end
      end

      def failing_endpoints
        RecordingStudioApi::Admin::Queries::AdminApiEndpointFailuresQuery
          .call(start_date: daily_buckets.first, end_date: Date.current)
          .sort_by { |row| [-row.failure_count, -row.server_error_count, row.request_method.to_s, row.request_path.to_s] }
          .first(LIMIT)
          .map do |row|
            {
              request_method: row.request_method,
              request_path: row.request_path,
              error_count: row.failure_count,
              server_error_count: row.server_error_count,
              dominant_status_code: row.dominant_status_code
            }
          end
      end

      def link_to(context)
        query = {
          start_date: daily_buckets.first.iso8601,
          end_date: Date.current.iso8601
        }

        "#{context.admin_screen_path('admin_api_failing_endpoints')}?#{query.to_query}"
      end

      def daily_buckets
        27.downto(0).map { |days_ago| Date.current - days_ago.days }
      end

      def time_range
        daily_buckets.first.beginning_of_day..Time.current
      end
    end
  end
end