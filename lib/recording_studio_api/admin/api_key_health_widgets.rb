# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    module ApiKeyHealthWidgets
      ENTRIES = [
        {
          widget_key: "widgets.recording_studio_api.admin.api_keys_expiring_soon",
          health: "expiring_soon",
          title: "Expiring soon",
          description: "Active keys that expire in the next 30 days.",
          link_label: "Review expiring keys"
        },
        {
          widget_key: "widgets.recording_studio_api.admin.api_keys_stale",
          health: "stale",
          title: "Stale keys",
          description: "Active keys unused for 90 days, or never used and older than that.",
          link_label: "Review stale keys"
        }
      ].freeze

      SCOPES = {
        "expiring_soon" => RecordingStudioApi::Metrics::EXPIRING_SOON,
        "stale" => RecordingStudioApi::Metrics::STALE
      }.freeze

      # Same default as AdminApiCredentialsScreen's status filter.
      LIST_STATUS = "active"

      Definitions = ENTRIES.map do |entry|
        ::RecordingStudioAdmin::Widget.new(
          nil,
          registry_prefix: entry.fetch(:widget_key)
        ) do
          type :number
          title entry.fetch(:title)
          description entry.fetch(:description)
          change_good_when :down
          hide_change
          value do |context|
            RecordingStudioApi::Admin::ApiKeyHealthWidgets.listed_count(context, entry.fetch(:health))
          end
          link_to do |context|
            NavigationUrlHelpers.admin_screen_url(
              context,
              "admin_api_credentials",
              health: entry.fetch(:health)
            )
          end
          link_label entry.fetch(:link_label)
        end
      end.freeze

      module_function

      def listed_count(context, health)
        listed_rows(context, health).size
      end

      def listed_rows(context, health)
        rows = RecordingStudioApi::Admin::Queries::AdminApiCredentialsQuery.call(
          api: RecordingStudioApi::Admin::ApiContext.key_from_context(context)
        )
        filter_rows(apply_status(rows, LIST_STATUS), health)
      end

      def apply_status(rows, value)
        value.present? ? rows.select { |row| row.status.casecmp?(value.to_s) } : rows
      end

      def filter_rows(rows, value)
        scope = SCOPES[value.to_s]
        return rows if scope.nil?

        ids = scope.call(ApiCredential.where(id: rows.map { |row| row.api_credential.id })).pluck(:id)
        rows.select { |row| ids.include?(row.api_credential.id) }
      end
    end
  end
end
