# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    class ApiKeysScreen < ::RecordingStudioAdmin::Screen
      key "api_keys"
      icon :key
      title "API keys"
      subtitle do |context|
        "API keys for #{workspace_name(context)}"
      end

      query do |context|
        RecordingStudioApi::Admin::Queries::ApiAccessClientsQuery.call(context)
      end

      filter :status, values: %w[active expired revoked missing], default: "active", apply: lambda { |rows, value, _context|
        case value.to_s
        when "active" then rows.select { |row| row.status == "Active" }
        when "expired" then rows.select { |row| row.status == "Expired" }
        when "revoked" then rows.select { |row| row.status == "Revoked" }
        when "missing" then rows.select { |row| row.status == "No credentials" }
        else rows
        end
      }

      summary do
        label "API keys"
        change_good_when :neutral
      end

      table do
        filter :search, apply: lambda { |rows, value, _context|
          next rows if value.blank?

          query = value.to_s.downcase
          rows.select do |row|
            [row.name, row.api_key, row.access_point, row.role].any? { |entry| entry.to_s.downcase.include?(query) }
          end
        }

        column :name,
               title: "Name",
               sortable: false,
               value: lambda { |row, context|
                 context.controller.view_context.link_to(
                   row.name,
                   context.controller.recording_studio_api.api_client_path(
                     row.api_client.id,
                     close_url: context.admin_screen_path("api_keys")
                   ),
                   data: { turbo_frame: "_top" }
                 )
               }
        column :api_key, title: "API key", sortable: false
        column :access_point, title: "Access point", sortable: false
        column :role, title: "Role", sortable: false
        column :status,
               title: "Status",
               sortable: false,
               display: :badge,
               display_options: ->(_row, _context, value) { RecordingStudioApi::Admin::ApiKeysScreen.status_badge_options(value) }
        column :request_count, title: "Requests", sortable: false
        column :last_requested_at, title: "Last request", sortable: false
        column :expires_text, title: "Expires", sortable: false
        default_columns :name, :api_key, :access_point, :role, :status, :request_count, :last_requested_at
        paginate per_page: 25, mode: :infinite

        action :edit,
               text: "Edit",
               icon: "pencil-square",
               url: lambda { |row, context|
                 context.controller.recording_studio_api.edit_api_client_path(
                   row.api_client.id,
                   close_url: context.admin_screen_path("api_keys")
                 )
               }

        # Removed rotate and revoke actions from the UI per admin request.
      end
      class << self
        def workspace_name(context)
          recordable = context.root_recording&.recordable || context.access_recordable
          return "this workspace" if recordable.nil?

          %i[name title label slug identifier].each do |attribute|
            next unless recordable.respond_to?(attribute)

            value = recordable.public_send(attribute)
            return value if value.present?
          end

          "this workspace"
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

        def manageable?(row, context)
          RecordingStudioApi::AccessManagementPolicy.new(actor: context.current_actor)
                                                    .can_manage_recording?(row.access_point_recording)
        end
      end
    end
  end
end