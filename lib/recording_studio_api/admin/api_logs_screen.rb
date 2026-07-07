# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    class ApiLogsScreen < ::RecordingStudioAdmin::Screen
      key "api_logs"
      icon :queue_list
      title "API logs"
      subtitle "Request log entries recorded by the API logging database."
      blast_radius :site

      query do |_context|
        if RecordingStudioApi::ApiRequestLog.table_available?
          RecordingStudioApi::ApiRequestLog.all
        else
          RecordingStudioApi::ApiRequestLog.none
        end
      end

      filter :date_range, field: :occurred_at, default: :last_30_days
      filter :status, values: %w[success redirect client_error server_error], apply: lambda { |relation, value, _context|
        case value.to_s
        when "success" then relation.where(status_code: 200..299)
        when "redirect" then relation.where(status_code: 300..399)
        when "client_error" then relation.where(status_code: 400..499)
        when "server_error" then relation.where(status_code: 500..599)
        else relation
        end
      }
      filter :rate_limited, values: %w[yes no], apply: lambda { |relation, value, _context|
        case value.to_s
        when "yes" then relation.where(rate_limited: true)
        when "no" then relation.where(rate_limited: [false, nil])
        else relation
        end
      }
      filter :path, param: :search, apply: lambda { |relation, value, _context|
        value.present? ? relation.where("request_path LIKE ?", "%#{RecordingStudioApi::Admin::ApiLogsScreen.sanitize_like(value)}%") : relation
      }

      summary do
        label "Total log entries"
        change_good_when :neutral
      end

      table do
        filter :search, apply: lambda { |relation, value, _context|
          value.present? ? relation.where("request_path LIKE ?", "%#{RecordingStudioApi::Admin::ApiLogsScreen.sanitize_like(value)}%") : relation
        }

        column :occurred_at, title: "Occurred"
        column :request_method, title: "Method"
        column :request_path, title: "Path"
        column :status_code,
               title: "Status",
               display: :badge,
               display_options: ->(_row, _context, value) { RecordingStudioApi::Admin::ApiLogsScreen.status_badge_options(value) }
        column :rate_limited,
               title: "Rate limited",
               display: :badge,
               display_options: ->(_row, _context, value) { RecordingStudioApi::Admin::ApiLogsScreen.rate_limited_badge_options(value) }
        column :remote_ip, title: "IP address"
        column :duration_ms, title: "Duration"
        column :request_id, title: "Request ID"
        default_columns :occurred_at, :request_method, :request_path, :status_code, :rate_limited, :remote_ip, :duration_ms
        default_sort :occurred_at, direction: :desc
        paginate per_page: 25, mode: :infinite
      end

      widget :total_requests do
        type :number
        title "API requests"
        value { |context| context.query_result&.count || RecordingStudioApi::ApiRequestLog.count }
        change { |context| RecordingStudioApi::Admin::ApiLogsScreen.format_change(context.query_result&.change_percent, precision: 0) }
        change_good_when :up
        link_to { |context| context.admin_screen_path("api_logs") }
      end

      widget :rate_limited_requests do
        type :number
        title "Rate limited"
        value do |context|
          RecordingStudioApi::Admin::ApiLogsScreen.rate_limited_count(context.query_result&.relation)
        end
        change do |context|
          current = RecordingStudioApi::Admin::ApiLogsScreen.rate_limited_count(context.query_result&.relation)
          previous = RecordingStudioApi::Admin::ApiLogsScreen.previous_rate_limited_count(context)

          RecordingStudioApi::Admin::ApiLogsScreen.format_change(
            RecordingStudioApi::Admin::ApiLogsScreen.percent_change(current, previous),
            precision: 0
          )
        end
        change_good_when :down
        link_to { |context| "#{context.admin_screen_path('api_logs')}?rate_limited=yes" }
      end

      class << self
        def sanitize_like(value)
          ActiveRecord::Base.sanitize_sql_like(value.to_s)
        end

        def rate_limited_count(relation)
          relation = RecordingStudioApi::ApiRequestLog.all if relation.nil?
          relation.where(rate_limited: true).or(relation.where(status_code: 429)).count
        end

        def previous_date_range(context)
          start_date, end_date = date_range_from_context(context)
          span_days = (end_date - start_date).to_i + 1
          previous_end = start_date - 1.day
          previous_start = previous_end - (span_days - 1).days
          [previous_start, previous_end]
        end

        def previous_scope(context)
          prev_start, prev_end = previous_date_range(context)
          RecordingStudioApi::ApiRequestLog.where(occurred_at: prev_start.beginning_of_day..prev_end.end_of_day)
        end

        def previous_rate_limited_count(context)
          rate_limited_count(previous_scope(context))
        end

        def date_range_from_context(context)
          filter_value = context.filter_value(:date_range)
          start_date = filter_value&.start_date || 29.days.ago.to_date
          end_date = filter_value&.end_date || Date.current
          [start_date, end_date]
        end

        def percent_change(current, previous)
          return nil if previous.nil? || current.nil?
          return 0 if previous.zero? && current.zero?
          return 100 if previous.zero? && current.positive?

          ((current - previous) / previous.to_f) * 100
        end

        def format_change(value, precision: 1)
          return nil if value.nil?
          return "0%" if value.to_f.zero?

          change_val = value.to_f
          sign = change_val.positive? ? "+" : ""
          "#{sign}#{change_val.round(precision)}%"
        end

        def status_badge_options(value)
          status_code = value.to_i
          {
            text: value.to_s,
            size: :sm,
            style: case status_code
                   when 200..299 then :success
                   when 300..399 then :info
                   when 400..499 then :warning
                   when 500..599 then :danger
                   else :default
                   end
          }
        end

        def rate_limited_badge_options(value)
          rate_limited = ActiveModel::Type::Boolean.new.cast(value)
          {
            text: rate_limited ? "Yes" : "No",
            size: :sm,
            style: rate_limited ? :danger : :default
          }
        end
      end
    end
  end
end