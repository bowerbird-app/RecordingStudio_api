# frozen_string_literal: true

begin
  require "recording_studio_admin"
rescue LoadError
  nil
end

require "recording_studio_api/admin/select_filter_default_patch"

module RecordingStudioApi
  module Admin
    DEFINITION_FILES = %w[
      recording_studio_api/admin/api_request_log_helpers
      recording_studio_api/admin/queries/api_access_clients_query
      recording_studio_api/admin/api_requests_last_four_weeks_widget
      recording_studio_api/admin/most_used_api_keys_widget
      recording_studio_api/admin/api_section
      recording_studio_api/admin/api_keys_screen
      recording_studio_api/admin/api_access_requests_screen
    ].freeze

    module_function

    # rubocop:disable Naming/PredicateMethod
    def available?
      defined?(::RecordingStudioAdmin::Section) && defined?(::RecordingStudioAdmin::Screen)
    end

    def register!
      return false unless available?

      load_definitions!
      ::RecordingStudioAdmin.register_section(ApiSection)
      ::RecordingStudioAdmin.register_widget(ApiRequestsLastFourWeeksWidget::Definition)
      ::RecordingStudioAdmin.register_widget(MostUsedApiKeysWidget::Definition)
      ::RecordingStudioAdmin.register_screen(ApiKeysScreen)
      ::RecordingStudioAdmin.register_screen(ApiAccessRequestsScreen)
      true
    end
    # rubocop:enable Naming/PredicateMethod

    def load_definitions!
      DEFINITION_FILES.each { |path| require path }
    end
  end
end