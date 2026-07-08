# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    class ApiAccessRequestsScreen < ::RecordingStudioAdmin::Screen
      key "api_requests"
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

      table do
        filter :search, apply: lambda { |relation, value, _context|
          value.present? ? relation.where("request_path LIKE ?", "%#{RecordingStudioApi::Admin::ApiRequestLogHelpers.sanitize_like(value)}%") : relation
        }

        column :occurred_at, title: "Occurred"
        column :request_method, title: "Method"
        column :request_path, title: "Path"
        column :status_code,
               title: "Status",
               display: :badge,
               display_options: ->(_row, _context, value) { RecordingStudioApi::Admin::ApiRequestLogHelpers.status_badge_options(value) }
        column :rate_limited,
               title: "Rate limited",
               display: :badge,
               display_options: ->(_row, _context, value) { RecordingStudioApi::Admin::ApiRequestLogHelpers.rate_limited_badge_options(value) }
        column :duration_ms, title: "Duration"
        column :request_id, title: "Request ID"
        default_columns :occurred_at, :request_method, :request_path, :status_code, :rate_limited, :duration_ms
        default_sort :occurred_at, direction: :desc
        paginate per_page: 25, mode: :infinite
      end

      class << self
        def api_client_name(context)
          requested_credential_id = context.params[:api_credential_id].presence || context.params["api_credential_id"].presence
          if requested_credential_id.present?
            credential = RecordingStudioApi::ApiCredential.includes(:api_client).find_by(id: requested_credential_id)
            return credential&.api_client&.name
          end

          requested_client_id = context.params[:api_client_id].presence || context.params["api_client_id"].presence
          return if requested_client_id.blank?

          RecordingStudioApi::ApiClient.where(id: requested_client_id).pick(:name)
        end

        def request_scope(context)
          credential_ids = visible_credential_ids(context)
          scope = RecordingStudioApi::ApiRequestLog.where(api_credential_id: credential_ids)

          requested_credential_id = context.params[:api_credential_id].presence || context.params["api_credential_id"].presence
          if requested_credential_id.present?
            return credential_ids.map(&:to_s).include?(requested_credential_id.to_s) ? scope.where(api_credential_id: requested_credential_id) : scope.none
          end

          requested_client_id = context.params[:api_client_id].presence || context.params["api_client_id"].presence
          return scope if requested_client_id.blank?

          visible_client_ids = visible_client_ids(context)
          visible_client_ids.map(&:to_s).include?(requested_client_id.to_s) ? scope.where(api_client_id: requested_client_id) : scope.none
        end

        def visible_credential_ids(context)
          RecordingStudioApi::Admin::Queries::ApiAccessClientsQuery.call(context).map(&:id)
        end

        def visible_client_ids(context)
          RecordingStudioApi::Admin::Queries::ApiAccessClientsQuery.call(context).map { |row| row.api_client.id }.uniq
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
      end
    end
  end
end