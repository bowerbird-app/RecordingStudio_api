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
           url: ->(context) { context.admin_screen_path("admin_api_requests") },
           style: :default

       link :failing_endpoints,
         text: "Failing endpoints",
         url: ->(context) { context.admin_screen_path("admin_api_failing_endpoints") },
         style: :default

       link :credentials,
         text: "API credentials",
         url: ->(context) { context.admin_screen_path("admin_api_credentials") },
         style: :default

      widget "widgets.recording_studio_api.admin.requests_last_four_weeks"
      widget "widgets.recording_studio_api.admin.api_latency_last_four_weeks"
      widget "widgets.recording_studio_api.admin.client_errors_last_four_weeks"
      widget "widgets.recording_studio_api.admin.server_errors_last_four_weeks"
      widget "widgets.recording_studio_api.admin.authorization_failures_last_four_weeks"
      widget "widgets.recording_studio_api.admin.top_failing_endpoints_last_four_weeks"
      widget "widgets.recording_studio_api.admin.rate_limited_requests_last_four_weeks"
    end
  end
end