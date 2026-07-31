# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    class AdminApiSection < ::RecordingStudioAdmin::Section
      key "admin_api"
      icon :queue_list
      title "Admin API"
      subtitle "Monitor and administer API access across the site."

      link :requests,
           text: "API requests",
           url: ->(context) { admin_screen_url(context, "admin_api_requests") },
           style: :default

      link :failing_endpoints,
           text: "Failing endpoints",
           url: ->(context) { admin_screen_url(context, "admin_api_failing_endpoints") },
           style: :default

      link :credentials,
           text: "API credentials",
           url: ->(context) { admin_screen_url(context, "admin_api_credentials") },
           style: :default

      link :new_credential,
           text: "Create API credential",
           url: lambda { |context|
             context.controller.recording_studio_api.new_api_client_path(
               root_recording_id: context.root_recording&.id,
               close_url: admin_screen_url(context, "admin_api_credentials"),
               anchor_url: context.params[:anchor_url] || context.params["anchor_url"]
             )
           },
           style: :primary

      link :settings,
           text: "API settings",
           url: ->(context) { api_settings_url(context) },
           style: :default

      widget "widgets.recording_studio_api.admin.requests_last_four_weeks"
      widget "widgets.recording_studio_api.admin.api_latency_last_four_weeks"
      widget "widgets.recording_studio_api.admin.client_errors_last_four_weeks"
      widget "widgets.recording_studio_api.admin.server_errors_last_four_weeks"
      widget "widgets.recording_studio_api.admin.authorization_failures_last_four_weeks"
      widget "widgets.recording_studio_api.admin.top_failing_endpoints_last_four_weeks"
      widget "widgets.recording_studio_api.admin.rate_limited_requests_last_four_weeks"

      def self.admin_screen_url(context, key)
        NavigationUrlHelpers.admin_screen_url(context, key)
      end

      def self.api_settings_url(context)
        RecordingStudioApi.admin_settings_path(
          controller: context.controller,
          anchor_url: context.params[:anchor_url] || context.params["anchor_url"]
        )
      end
    end
  end
end