# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    class AdminApiRequestsScreen < ::RecordingStudioAdmin::Screen
      key "admin_api_requests"
      icon :queue_list
      title "API requests"
      subtitle "Site-wide API request activity across every API client."

      query do |context|
        if RecordingStudioApi::Admin::ApiAuthorization.authorized?(
          actor: context.current_actor,
          api: RecordingStudioApi::Admin::ApiContext.key_from_context(context),
          root_recording: context.root_recording,
          role: RecordingStudioApi.configuration.access_management_view_role
        ) && RecordingStudioApi::ApiRequestLog.table_available?
          RecordingStudioApi::ApiRequestLog.where(api_key: RecordingStudioApi::Admin::ApiContext.key_from_context(context))
        else
          RecordingStudioApi::ApiRequestLog.none
        end
      end

      filter :date_range, field: :occurred_at, default: :this_month
      filter :group_by, values: %i[hour day week month year], default: :day
      filter_presentation :modal, inline_count: 2
      filter :api_client_name,
             options: -> { RecordingStudioApi::Admin::AdminApiRequestsScreen.api_client_name_filter_options },
             blank_label: "All API clients",
             placeholder: nil,
             humanize_options: false,
             apply: lambda { |relation, value, context|
               if value.present?
                 relation.where(api_client_id: RecordingStudioApi::ApiClient.where(api_key: RecordingStudioApi::Admin::ApiContext.key_from_context(context), name: value).pluck(:id))
               else
                 relation
               end
             }
      filter :status, values: %w[success redirect client_error authorization_failure server_error failed], placeholder: "Status", apply: lambda { |relation, value, _context|
        case value.to_s
        when "success" then relation.where(status_code: 200..299)
        when "redirect" then relation.where(status_code: 300..399)
        when "client_error" then relation.where(status_code: 400..499)
        when "authorization_failure" then relation.where(status_code: [401, 403])
        when "server_error" then relation.where(status_code: 500..599)
        when "failed" then relation.where(status_code: 400..599).where.not(status_code: 429)
        else relation
        end
      }
      filter :rate_limited, values: %w[true false], placeholder: "Rate limited", apply: lambda { |relation, value, _context|
        case value.to_s
        when "true" then relation.where(rate_limited: true)
        when "false" then relation.where(rate_limited: false)
        else relation
        end
      }
      filter :request_path, placeholder: "Request path", apply: lambda { |relation, value, _context|
        value.present? ? relation.where(request_path: value) : relation
      }

      summary do
        label "API requests"
        change_good_when :neutral
      end

      chart do
        title "API requests"
        type :area
        series lambda { |context|
          RecordingStudioApi::Admin::AdminApiRequestsScreen.request_series(context)
        }
        options lambda { |_context|
          {
            xaxis: { labels: { rotate: -45, hideOverlappingLabels: true } },
            yaxis: { min: 0, forceNiceScale: true },
            stroke: { curve: "smooth", width: 2 },
            dataLabels: { enabled: false },
            fill: { opacity: 0.24 }
          }
        }
      end

      table do
        filter :search, apply: lambda { |relation, value, _context|
          value.present? ? relation.where("request_path LIKE ?", "%#{RecordingStudioApi::Admin::ApiRequestLogHelpers.sanitize_like(value)}%") : relation
        }

        column :occurred_at, title: "Occurred"
        column :api_client_name, title: "Client", sortable: false
        column :request_method, title: "Method"
        column :request_path,
               title: "Path",
               value: ->(row, _context) { RecordingStudioApi::Admin::ApiRequestLogHelpers.compact_path(row.request_path) },
               tooltip: ->(row, _context) { row.request_path }
        column :status_code,
               title: "Status",
               display: :badge,
               display_options: ->(_row, _context, value) { RecordingStudioApi::Admin::ApiRequestLogHelpers.status_badge_options(value) }
        column :rate_limited,
               title: "Rate limited",
               display: :badge,
               display_options: ->(_row, _context, value) { RecordingStudioApi::Admin::ApiRequestLogHelpers.rate_limited_badge_options(value) }
        column :duration_ms, title: "Duration"
        column :remote_ip, title: "IP address"
        column :request_id, title: "Request ID"
        default_columns :occurred_at, :api_client_name, :request_method, :request_path, :status_code, :rate_limited, :duration_ms, :remote_ip
        default_sort :occurred_at, direction: :desc
        paginate per_page: 25, mode: :infinite
      end

      class << self
        def request_series(context)
          result = context.query_result
          return [] if result.nil? || result.count < 1

          bucket = (context.filter_value(:group_by) || :day).to_sym
          buckets = RecordingStudioApi::Admin::ApiAccessRequestsScreen.chart_buckets(context, bucket)
          return [] if buckets.empty?

          counts = buckets.index_with(0)
          result.relation.reorder(nil).pluck(:occurred_at).each do |occurred_at|
            next if occurred_at.nil?

            bucket_start = RecordingStudioApi::Admin::ApiAccessRequestsScreen.chart_bucket_start(occurred_at, bucket)
            counts[bucket_start] += 1 if counts.key?(bucket_start)
          end

          [{
            name: "API requests",
            data: buckets.map do |bucket_start|
              {
                x: RecordingStudioApi::Admin::ApiAccessRequestsScreen.chart_bucket_label(bucket_start, bucket),
                y: counts.fetch(bucket_start, 0)
              }
            end
          }]
        end

        def api_client_name_filter_options
          names = RecordingStudioApi::ApiClient.distinct.order(:name).pluck(:name).compact
          [""] + names
        end
      end
    end
  end
end