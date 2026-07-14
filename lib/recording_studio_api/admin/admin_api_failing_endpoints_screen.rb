# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    class AdminApiFailingEndpointsScreen < ::RecordingStudioAdmin::Screen
      key "admin_api_failing_endpoints"
      icon :exclamation_triangle
      title "Failing endpoints"
      subtitle "Site-wide endpoint failures relative to total API request volume."

      query do |context|
        RecordingStudioApi::Admin::AdminApiFailingEndpointsScreen.endpoint_rows(context)
      end

      filter :date_range, default: :last_4_weeks

      summary do
        label "Failing endpoints"
        hide_change
        change_good_when :down
      end

      chart do
        title "Failure rate by endpoint"
        type :bar
        series lambda { |context|
          RecordingStudioApi::Admin::AdminApiFailingEndpointsScreen.failure_rate_series(context)
        }
        options lambda { |context|
          {
            plotOptions: { bar: { horizontal: true } },
            xaxis: {
              categories: RecordingStudioApi::Admin::AdminApiFailingEndpointsScreen.failure_rate_categories(context),
              max: 100,
              title: { text: "Failure rate (%)" }
            },
            yaxis: { labels: { maxWidth: 300 } },
            dataLabels: { enabled: false }
          }
        }
      end

      table do
        filter :search, apply: lambda { |rows, value, _context|
          next rows if value.blank?

          query = value.to_s.downcase
          rows.select { |row| [row.request_method, row.request_path].any? { |value| value.to_s.downcase.include?(query) } }
        }

        column :request_method, title: "Method", sortable: false
        column :request_path, title: "Path", sortable: false
        column :failure_count, title: "Failed requests", sortable: false
        column :total_request_count, title: "Total requests", sortable: false
        column :failure_rate, title: "Failure rate", sortable: false, value: ->(row, _context) { format("%.1f%%", row.failure_rate * 100) }
        column :client_error_count, title: "Client errors", sortable: false
        column :server_error_count, title: "Server errors", sortable: false
        column :dominant_status_code,
               title: "Dominant status",
               sortable: false,
               display: :badge,
               display_options: ->(_row, _context, value) { RecordingStudioApi::Admin::ApiRequestLogHelpers.status_badge_options(value) }
        default_columns :request_method, :request_path, :failure_count, :total_request_count, :failure_rate, :client_error_count, :server_error_count, :dominant_status_code
        paginate per_page: 25, mode: :infinite
      end

      class << self
        def endpoint_rows(context)
          start_date, end_date = date_range_from_context(context)
          RecordingStudioApi::Admin::Queries::AdminApiEndpointFailuresQuery.call(start_date:, end_date:)
        end

        def failure_rate_series(context)
          [{
            name: "Failure rate (%)",
            data: failure_rate_rows(context).map { |row| (row.failure_rate * 100).round(1) }
          }]
        end

        def failure_rate_categories(context)
          failure_rate_rows(context).map { |row| "#{row.request_method} #{row.request_path}" }
        end

        def date_range_from_context(context)
          filter_value = context.filter_value(:date_range)
          start_date = filter_value&.start_date || 27.days.ago.to_date
          end_date = filter_value&.end_date || Date.current
          start_date > end_date ? [end_date, start_date] : [start_date, end_date]
        end

        def failure_rate_rows(context)
          endpoint_rows(context).first(10).reverse
        end
      end
    end
  end
end