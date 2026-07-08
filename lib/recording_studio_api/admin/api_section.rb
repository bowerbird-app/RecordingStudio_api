# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    class ApiSection < ::RecordingStudioAdmin::Section
      key "api"
      icon :key
      title "API"
      subtitle "Manage API keys and inspect request usage for this workspace."

      link :new_client,
           text: "Create API key",
           url: lambda { |context|
             context.controller.recording_studio_api.new_api_client_path(
               root_recording_id: context.root_recording&.id,
               close_url: context.admin_screen_path("api_keys")
             )
           },
           style: :primary

      link :clients,
           text: "View API keys",
           url: ->(context) { context.admin_screen_path("api_keys") },
           style: :default

      link :requests,
           text: "View requests",
           url: ->(context) { context.admin_screen_path("api_requests") },
           style: :secondary
    end
  end
end