# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    class ApiAccessRequestsScreen < ::RecordingStudioAdmin::Screen
      key "api_access_requests"
      icon :queue_list
      title "API requests"
      subtitle do |context|
        api_client_name = api_client_name(context)
        api_client_name.present? ? "Request activity for #{api_client_name}." : "Request activity for API keys available in this workspace."
      end

      query do |context|
        if RecordingStudioApi::ApiRequestLog.table_available?
          RecordingStudioApi::Admin::ApiAccessRequestsScreen.request_scope(context)
        else
          RecordingStudioApi::ApiRequestLog.none
        end
      end

      filter :date_range, field: :occurred_at, default: :this_month
      filter :status, values: %w[success redirect client_error server_error], apply: lambda { |relation, value, _context|
        case value.to_s
        when "success" then relation.where(status_code: 200..299)
        when "redirect" then relation.where(status_code: 300..399)
        when "client_error" then relation.where(status_code: 400..499)
        when "server_error" then relation.where(status_code: 500..599)
        else relation
        end
      }

      summary do
        label "API requests"
        change_good_when :neutral
      end

      chart do
        title "Requests over time"
        type :column
        series lambda { |context|
          result = context.query_result
          return [] if result.nil? || result.count < 1

          relation = result.relation
          start_date, end_date = RecordingStudioApi::Admin::ApiAccessRequestsScreen.date_range_from_context(context)
          counts_by_date = relation
                           .where(occurred_at: start_date.beginning_of_day..end_date.end_of_day)
                           .group("DATE(occurred_at)")
                           .order("DATE(occurred_at)")
                           .count

          date_range = start_date.to_date..end_date.to_date
          data = date_range.map { |day| counts_by_date.fetch(day, counts_by_date.fetch(day.to_s, 0)) }
          [{ name: "Requests", data: data }]
        }
        options lambda { |context|
          start_date, end_date = RecordingStudioApi::Admin::ApiAccessRequestsScreen.date_range_from_context(context)
          categories = (start_date.to_date..end_date.to_date).map { |day| day.strftime("%b %-d") }
          {
            xaxis: {
              categories: categories,
              labels: { rotate: -45, hideOverlappingLabels: true }
            },
            yaxis: { min: 0, forceNiceScale: true },
            stroke: { width: 0 },
            dataLabels: { enabled: false }
          }
        }
      end

      widget :total_requests do
        type :number
        title "API requests"
        value { |context| context.query_result&.count || 0 }
        change { |context| RecordingStudioApi::Admin::ApiAccessRequestsScreen.format_change(context.query_result&.change_percent, precision: 0) }
        metadata { |context| { period_label: context.period_label } }
        change_good_when :up
      end

      widget :avg_duration do
        type :number
        title "Avg duration"
        metadata lambda { |context|
          { unit_label: "ms", period_label: context.period_label }
        }
        value lambda { |context|
          result = context.query_result
          next 0 if result.nil? || result.count < 1

          result.relation.average(:duration_ms)&.round(0) || 0
        }
        change lambda { |context|
          current_val = context.query_result&.relation&.average(:duration_ms)
          previous_val = RecordingStudioApi::Admin::ApiAccessRequestsScreen.previous_avg_duration(context)
          RecordingStudioApi::Admin::ApiAccessRequestsScreen.format_change(
            RecordingStudioApi::Admin::ApiAccessRequestsScreen.percent_change(current_val, previous_val),
            precision: 0
          )
        }
        change_good_when :down
      end

      widget :error_rate do
        type :number
        title "Error rate"
        metadata lambda { |context|
          { unit_label: "%", period_label: context.period_label }
        }
        value lambda { |context|
          result = context.query_result
          next 0 if result.nil? || result.count < 1

          total = result.count
          errors = result.relation.where(status_code: 400..599).count
          (errors.to_f / total * 100).round(1)
        }
        change lambda { |context|
          result = context.query_result
          next nil if result.nil? || result.count < 1

          total = result.count
          errors = result.relation.where(status_code: 400..599).count
          current_rate = total.positive? ? (errors.to_f / total * 100).round(1) : 0

          prev_total, prev_errors = RecordingStudioApi::Admin::ApiAccessRequestsScreen.previous_error_counts(context)
          previous_rate = prev_total&.positive? ? (prev_errors.to_f / prev_total * 100).round(1) : nil

          RecordingStudioApi::Admin::ApiAccessRequestsScreen.format_change(
            RecordingStudioApi::Admin::ApiAccessRequestsScreen.percent_change(current_rate, previous_rate),
            precision: 0
          )
        }
        change_good_when :down
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
        column :duration_ms, title: "Duration"
        column :request_id, title: "Request ID"
        default_columns :occurred_at, :request_method, :request_path, :status_code, :rate_limited, :duration_ms
        default_sort :occurred_at, direction: :desc
        paginate per_page: 25, mode: :infinite
      end

      class << self
        def api_client_name(context)
          requested_client_id = context.params[:api_client_id].presence || context.params["api_client_id"].presence
          return if requested_client_id.blank?

          RecordingStudioApi::ApiClient.where(id: requested_client_id).pick(:name)
        end

        def request_scope(context)
          client_ids = visible_client_ids(context)
          scope = RecordingStudioApi::ApiRequestLog.where(api_client_id: client_ids)

          requested_client_id = context.params[:api_client_id].presence || context.params["api_client_id"].presence
          return scope if requested_client_id.blank?

          client_ids.map(&:to_s).include?(requested_client_id.to_s) ? scope.where(api_client_id: requested_client_id) : scope.none
        end

        def visible_client_ids(context)
          RecordingStudioApi::Admin::Queries::ApiAccessClientsQuery.call(context).map(&:id)
        end

        def date_range_from_context(context)
          filter_value = context.filter_value(:date_range)
          start_date = filter_value&.start_date || 29.days.ago.to_date
          end_date = filter_value&.end_date || Date.current
          [start_date, end_date]
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
          base = RecordingStudioApi::Admin::ApiAccessRequestsScreen.request_scope(context)
          status_value = context.filter_value(:status)
          scope = base.where(occurred_at: prev_start.beginning_of_day..prev_end.end_of_day)
          case status_value.to_s
          when "success" then scope.where(status_code: 200..299)
          when "redirect" then scope.where(status_code: 300..399)
          when "client_error" then scope.where(status_code: 400..499)
          when "server_error" then scope.where(status_code: 500..599)
          else scope
          end
        end

        def previous_avg_duration(context)
          prev_scope = previous_scope(context)
          prev_scope.average(:duration_ms)
        end

        def previous_error_counts(context)
          prev_scope = previous_scope(context)
          total = prev_scope.count
          errors = prev_scope.where(status_code: 400..599).count
          [total, errors]
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
      end
    end
  end
end