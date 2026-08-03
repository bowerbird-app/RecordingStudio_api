# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    module GeneratedApiSections
    end

    module ApiSectionFactory
      module_function

      def user_section(api)
        definition = RecordingStudioApi.configuration.fetch_api(api)
        return ApiSection if definition.name == "public"

        generated_section(:user, definition) do |section|
          section.key user_section_key(definition.name)
          section.icon :key
          section.title "#{definition.name.humanize} API"
          section.subtitle "Manage #{definition.name.humanize.downcase} API keys and inspect request usage."

          section.link :new_client,
                       text: "Create API key",
                       url: lambda { |context|
                         context.controller.recording_studio_api.new_api_client_path(
                           api_key: definition.name,
                           root_recording_id: context.root_recording&.id,
                           close_url: NavigationUrlHelpers.admin_screen_url(context, "api_keys", api_key: definition.name),
                           anchor_url: context.params[:anchor_url] || context.params["anchor_url"]
                         )
                       },
                       style: :primary
          section.link :clients,
                       text: "API keys",
                       url: ->(context) { NavigationUrlHelpers.admin_screen_url(context, "api_keys", api_key: definition.name) },
                       style: :default
          section.link :requests,
                       text: "API requests",
                       url: ->(context) { NavigationUrlHelpers.admin_screen_url(context, "api_requests", api_key: definition.name) },
                       style: :secondary
          section.widget "widgets.recording_studio_api.requests_last_four_weeks", params: { api_key: definition.name }
          section.widget "widgets.recording_studio_api.most_used_keys", params: { api_key: definition.name }
        end
      end

      def admin_section(api)
        definition = RecordingStudioApi.configuration.fetch_api(api)
        return AdminApiSection if definition.name == "public"

        generated_section(:admin, definition) do |section|
          section.key admin_section_key(definition.name)
          section.icon :queue_list
          section.title "Admin #{definition.name.humanize} API"
          section.subtitle "Monitor and administer the #{definition.name.humanize.downcase} API across the site."
          section.visible_if lambda { |context|
            ApiAuthorization.authorized?(
              actor: context.current_actor,
              api: definition.name,
              root_recording: context.root_recording,
              role: RecordingStudioApi.configuration.access_management_view_role,
              create: true
            )
          }

          section.link :requests,
                       text: "API requests",
                       url: ->(context) { NavigationUrlHelpers.admin_screen_url(context, "admin_api_requests", api_key: definition.name) },
                       style: :default
          section.link :failing_endpoints,
                       text: "Failing endpoints",
                       url: ->(context) { NavigationUrlHelpers.admin_screen_url(context, "admin_api_failing_endpoints", api_key: definition.name) },
                       style: :default
          section.link :credentials,
                       text: "API credentials",
                       url: ->(context) { NavigationUrlHelpers.admin_screen_url(context, "admin_api_credentials", api_key: definition.name) },
                       style: :default
          section.link :new_credential,
                       text: "Create API credential",
                       url: lambda { |context|
                         context.controller.recording_studio_api.new_api_client_path(
                           api_key: definition.name,
                           root_recording_id: context.root_recording&.id,
                           close_url: NavigationUrlHelpers.admin_screen_url(context, "admin_api_credentials", api_key: definition.name),
                           anchor_url: context.params[:anchor_url] || context.params["anchor_url"]
                         )
                       },
                       style: :primary
          section.link :settings,
                       text: "API settings",
                       url: lambda { |context|
                         RecordingStudioApi.admin_settings_path(
                           controller: context.controller,
                           api_key: definition.name,
                           anchor_url: context.params[:anchor_url] || context.params["anchor_url"]
                         )
                       },
                       style: :default

          admin_widget_keys.each do |widget_key|
            section.widget widget_key, params: { api_key: definition.name }
          end
        end
      end

      def user_section_key(api_key)
        api_key.to_s == "public" ? "api" : "#{api_key}_api"
      end

      def admin_section_key(api_key)
        api_key.to_s == "public" ? "admin_api" : "admin_#{api_key}_api"
      end

      def generated_section(kind, definition)
        constant_name = "#{kind.to_s.camelize}#{definition.name.camelize}ApiSection"
        return GeneratedApiSections.const_get(constant_name, false) if GeneratedApiSections.const_defined?(constant_name, false)

        section = Class.new(::RecordingStudioAdmin::Section)
        yield section
        GeneratedApiSections.const_set(constant_name, section)
      end

      def admin_widget_keys
        %w[
          widgets.recording_studio_api.admin.requests_last_four_weeks
          widgets.recording_studio_api.admin.api_latency_last_four_weeks
          widgets.recording_studio_api.admin.client_errors_last_four_weeks
          widgets.recording_studio_api.admin.server_errors_last_four_weeks
          widgets.recording_studio_api.admin.authorization_failures_last_four_weeks
          widgets.recording_studio_api.admin.top_failing_endpoints_last_four_weeks
          widgets.recording_studio_api.admin.rate_limited_requests_last_four_weeks
        ]
      end
    end
  end
end
