# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    class AdminApiCredentialsScreen < ::RecordingStudioAdmin::Screen
      key "admin_api_credentials"
      icon :key
      title "API credentials"
      subtitle "Review and revoke API credentials across all roots."

      query do |_context|
        RecordingStudioApi::Admin::Queries::AdminApiCredentialsQuery.call
      end

      filter :status, values: [""] + %w[active expired revoked], apply: lambda { |rows, value, _context|
        value.present? ? rows.select { |row| row.status.casecmp?(value.to_s) } : rows
      }

      filter :root_recording_id,
             options: -> { root_filter_options },
             blank_label: "All roots",
             placeholder: nil,
             humanize_options: false,
             apply: lambda { |rows, value, _context|
               value.present? ? rows.select { |row| row.root == value } : rows
             }

      filter :root_type,
             options: -> { root_type_filter_options },
             blank_label: "All root types",
             placeholder: nil,
             humanize_options: false,
             apply: lambda { |rows, value, _context|
               value.present? ? rows.select { |row| row.root_type == value } : rows
             }

      summary do
        label "API credentials"
        change_good_when :neutral
      end

      table do
        filter :search, apply: lambda { |rows, value, _context|
          next rows if value.blank?

          query = value.to_s.downcase
          rows.select do |row|
            [row.root, row.root_type, row.api_client.name, row.api_key, row.access_point, row.role].any? do |entry|
              entry.to_s.downcase.include?(query)
            end
          end
        }

        column :root, title: "Root", sortable: false
        column :root_type, title: "Root type", sortable: false
        column :api_client_name, title: "Client", sortable: false, value: ->(row, _context) { row.api_client.name }
        column :api_key, title: "Credential", sortable: false
        column :access_point, title: "Access point", sortable: false
        column :role, title: "Role", sortable: false
        column :status,
               title: "Status",
               sortable: false,
               display: :badge,
           display_options: ->(_row, _context, value) { RecordingStudioApi::Admin::AdminApiCredentialsScreen.status_badge_options(value) }
        column :request_count, title: "Requests", sortable: false
        column :last_requested_at, title: "Last request", sortable: false
        column :expires_text, title: "Expires", sortable: false
        default_columns :root, :api_client_name, :api_key, :access_point, :role, :status, :last_requested_at
        paginate per_page: 25, mode: :infinite

        action :revoke,
               text: "Revoke",
               icon: "no-symbol",
               method: :post,
               destructive: true,
               confirm: "Revoke this API credential? This cannot be undone.",
               visible_if: ->(row, _context) { row.status == "Active" },
               url: lambda { |row, context|
                 context.controller.recording_studio_api.admin_revoke_credential_path(
                   row.id,
                   close_url: context.admin_screen_path("admin_api_credentials")
                 )
               }
      end

      class << self
        def root_filter_options
          [""] + RecordingStudioApi::Admin::Queries::AdminApiCredentialsQuery.call
                                                                              .map { |row| root_filter_value(row) }
                                                                              .uniq
                                                                              .sort
        end

        def root_filter_value(row)
          row.root
        end

        def root_type_filter_options
          [""] + RecordingStudioApi::Admin::Queries::AdminApiCredentialsQuery.call
                                                                              .map(&:root_type)
                                                                              .uniq
                                                                              .sort
        end

        def status_badge_options(value)
          {
            text: value.to_s,
            size: :sm,
            style: case value.to_s
                   when "Active" then :success
                   when "Expired" then :warning
                   when "Revoked" then :danger
                   else :default
                   end
          }
        end
      end
    end
  end
end