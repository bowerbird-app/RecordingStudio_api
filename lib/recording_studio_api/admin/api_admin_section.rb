# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    class ApiAdminSection < ::RecordingStudioAdmin::Section
      key "api_admin"
      icon :document_text
      title "API Admin"
      subtitle "Monitor API traffic, logs, errors, credentials, and rate limits."
      blast_radius :site

      link :logs,
           text: "View logs",
           url: ->(context) { context.admin_screen_path("api_logs") },
           style: :secondary

      widget "api_logs.widgets.total_requests", view_variant: :compact, params: { preset_key: :this_week }
      widget "api_logs.widgets.rate_limited_requests", view_variant: :compact, params: { preset_key: :this_week }
    end
  end
end