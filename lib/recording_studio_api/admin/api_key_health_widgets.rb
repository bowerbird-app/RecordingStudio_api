# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    module ApiKeyHealthWidgets
      ENTRIES = [
        {
          metric: "api_keys.expiring_soon",
          widget_key: "widgets.recording_studio_api.admin.api_keys_expiring_soon",
          health: "expiring_soon",
          title: "Expiring soon",
          description: "Active keys that expire in the next 30 days.",
          link_label: "Review expiring keys"
        },
        {
          metric: "api_keys.stale",
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
            RecordingStudioApi::Admin::ApiKeyHealthWidgets.scalar(context, entry.fetch(:metric))
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

      def scalar(context, identifier)
        RecordingStudioMetrics::Admin.scalar_value(
          identifier,
          admin_context: context,
          scope: :site,
          site_authorized: true
        )
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
