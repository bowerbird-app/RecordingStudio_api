# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    class ApiAccessSection < ::RecordingStudioAdmin::Section
      key "api"
      icon :key
      title "API"
      subtitle "Manage API keys and inspect request usage for this workspace."

      link :new_client,
           text: "Create API key",
           url: lambda { |context|
             context.controller.recording_studio_api.new_api_client_path(
               root_recording_id: context.root_recording&.id,
               close_url: context.admin_screen_path("api_access_clients")
             )
           },
           style: :primary

      link :clients,
           text: "View API keys",
           url: ->(context) { context.admin_screen_path("api_access_clients") },
           style: :default

      link :requests,
           text: "View requests",
           url: ->(context) { context.admin_screen_path("api_access_requests") },
           style: :secondary

      widget "api_access_requests.widgets.total_requests", view_variant: :card, params: { preset_key: :this_month }
    end
  end
end