# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    module MostUsedApiKeysWidget
      WIDGET_KEY = "widgets.recording_studio_api.most_used_keys"
      LIMIT = 5

      Definition = ::RecordingStudioAdmin::Widget.new(
        nil,
        registry_prefix: WIDGET_KEY
      ) do
        type :list
        title "Most used keys"
        description "API keys with the most requests over the last 4 weeks."
        metadata { { period_label: "Last 4 weeks" } }
        hide_metric
        hide_change
        list_options divider: true
        items { |context| RecordingStudioApi::Admin::MostUsedApiKeysWidget.items(context) }
        link_to { |context| NavigationUrlHelpers.admin_screen_url(context, "api_keys") }
        link_label "API keys"
      end

      module_function

      def items(context)
        rows = most_used_rows(context)
        return [{ text: "No API requests", trailing: "Last 4 weeks" }] if rows.empty?

        rows.map do |row|
          {
            text: row[:name],
            trailing: request_count_label(row[:request_count])
          }
        end
      end

      def most_used_rows(context)
        return [] unless RecordingStudioApi::ApiRequestLog.table_available?

        visible_rows = RecordingStudioApi::Admin::Queries::ApiAccessClientsQuery.call(context)
        name_by_credential_id = visible_rows.to_h { |row| [row.id, row.name.to_s.presence || "Unknown"] }
        return [] if name_by_credential_id.empty?

        counts_by_credential_id = request_scope(context)
                                  .where(occurred_at: time_range)
                                  .group(:api_credential_id)
                                  .count

        ranked = counts_by_credential_id.filter_map do |credential_id, request_count|
          name = name_by_credential_id[credential_id]
          next if name.blank?

          { credential_id: credential_id, name: name, request_count: request_count }
        end
        ranked.sort_by { |row| [-row[:request_count], row[:name].downcase, row[:credential_id].to_s] }.first(LIMIT)
      end

      def request_scope(context)
        RecordingStudioApi::Admin::ApiAccessRequestsScreen.request_scope(context)
      end

      def request_count_label(count)
        "#{count} #{'request'.pluralize(count)}"
      end

      def time_range
        RecordingStudioApi::Admin::ApiRequestsLastFourWeeksWidget.time_range
      end
    end
  end
end