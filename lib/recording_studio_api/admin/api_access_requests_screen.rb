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
      filter :group_by, values: %i[hour day week month year], default: :day
      filter :api_client_name,
             options: -> { RecordingStudioApi::Admin::ApiAccessRequestsScreen.api_client_name_filter_options },
             blank_label: "All API keys",
             placeholder: nil,
             humanize_options: false,
             apply: lambda { |relation, value, _context|
               if value.present?
                 relation.where(api_client_id: RecordingStudioApi::ApiClient.where(name: value).pluck(:id))
               else
                 relation
               end
             }
      filter :status, values: %w[success redirect client_error server_error], placeholder: "Status", apply: lambda { |relation, value, _context|
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
          RecordingStudioApi::Admin::ApiAccessRequestsScreen.stacked_request_series(context)
        }
        options lambda { |_context|
          {
            chart: { stacked: true },
            plotOptions: { bar: { horizontal: false } },
            xaxis: { labels: { rotate: -45, hideOverlappingLabels: true } },
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
        column :api_client_name, title: "Name", sortable: false
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
        default_columns :occurred_at, :api_client_name, :request_method, :request_path, :status_code, :rate_limited, :duration_ms
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

        def api_client_name_filter_options
          names = RecordingStudioApi::ApiClient.distinct.order(:name).pluck(:name).compact
          [""] + names
        end

        def date_range_from_context(context)
          filter_value = context.filter_value(:date_range)
          start_date = filter_value&.start_date || 29.days.ago.to_date
          end_date = filter_value&.end_date || Date.current
          [start_date, end_date]
        end

        def stacked_request_series(context)
          result = context.query_result
          return [] if result.nil? || result.count < 1

          bucket = (context.filter_value(:group_by) || :day).to_sym
          buckets = chart_buckets(context, bucket)
          return [] if buckets.empty?

          rows = result.relation.reorder(nil).pluck(:occurred_at, :api_credential_id)
          name_by_credential_id = api_key_names(rows.map(&:second).compact.uniq)
          counts = Hash.new(0)

          rows.each do |occurred_at, credential_id|
            next if occurred_at.nil?

            bucket_start = chart_bucket_start(occurred_at, bucket)
            series_name = name_by_credential_id.fetch(credential_id, "Unknown")
            counts[[series_name, bucket_start]] += 1
          end

          series_names = counts.keys.map(&:first).uniq.sort
          series_names.map do |series_name|
            {
              name: series_name,
              data: buckets.map do |bucket_start|
                { x: chart_bucket_label(bucket_start, bucket), y: counts.fetch([series_name, bucket_start], 0) }
              end
            }
          end
        end

        def api_key_names(credential_ids)
          return {} if credential_ids.empty?

          RecordingStudioApi::ApiCredential
            .includes(:api_client)
            .where(id: credential_ids)
            .each_with_object({}) do |credential, names|
              names[credential.id] = credential.api_client&.name.to_s.presence || "Unknown"
            end
        end

        def chart_buckets(context, bucket)
          start_date, end_date = date_range_from_context(context)
          start_bucket = chart_range_start(start_date, bucket)
          end_bucket = chart_range_end(end_date, bucket)
          buckets = []
          current_bucket = start_bucket

          while current_bucket <= end_bucket
            buckets << current_bucket
            current_bucket = next_chart_bucket(current_bucket, bucket)
          end

          buckets
        end

        def chart_range_start(date, bucket)
          case bucket
          when :hour then date.beginning_of_day.beginning_of_hour
          when :week then date.beginning_of_week.to_date
          when :month then date.beginning_of_month
          when :year then date.beginning_of_year
          else date.to_date
          end
        end

        def chart_range_end(date, bucket)
          case bucket
          when :hour then date.end_of_day.beginning_of_hour
          when :week then date.beginning_of_week.to_date
          when :month then date.beginning_of_month
          when :year then date.beginning_of_year
          else date.to_date
          end
        end

        def chart_bucket_start(value, bucket)
          case bucket
          when :hour then value.in_time_zone.beginning_of_hour
          when :week then value.to_date.beginning_of_week.to_date
          when :month then value.to_date.beginning_of_month
          when :year then value.to_date.beginning_of_year
          else value.to_date
          end
        end

        def next_chart_bucket(value, bucket)
          case bucket
          when :hour then value + 1.hour
          when :week then value + 1.week
          when :month then value.next_month.beginning_of_month
          when :year then value.next_year.beginning_of_year
          else value + 1.day
          end
        end

        def chart_bucket_label(value, bucket)
          timestamp = value.respond_to?(:in_time_zone) ? value.in_time_zone : value.to_time.in_time_zone

          case bucket
          when :hour then timestamp.strftime("%b %-d %-l%P")
          when :week then "Week of #{timestamp.strftime('%b %-d')}"
          when :month then timestamp.strftime("%b %Y")
          when :year then timestamp.strftime("%Y")
          else timestamp.strftime("%b %-d")
          end
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