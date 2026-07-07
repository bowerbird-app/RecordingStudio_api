# frozen_string_literal: true

begin
  require "recording_studio_admin"
rescue LoadError
  nil
end

module RecordingStudioApi
  module Admin
    DEFINITION_FILES = %w[
      recording_studio_api/admin/queries/api_access_clients_query
      recording_studio_api/admin/api_access_section
      recording_studio_api/admin/api_access_clients_screen
      recording_studio_api/admin/api_access_requests_screen
      recording_studio_api/admin/api_admin_section
      recording_studio_api/admin/api_logs_screen
    ].freeze

    module_function

    # rubocop:disable Naming/PredicateMethod
    def available?
      defined?(::RecordingStudioAdmin::Section) && defined?(::RecordingStudioAdmin::Screen)
    end

    def register!
      return false unless available?

      load_definitions!
      ::RecordingStudioAdmin.register_section(ApiAccessSection)
      ::RecordingStudioAdmin.register_section(ApiAdminSection)
      ::RecordingStudioAdmin.register_screen(ApiAccessClientsScreen)
      ::RecordingStudioAdmin.register_screen(ApiAccessRequestsScreen)
      ::RecordingStudioAdmin.register_screen(ApiLogsScreen)
      true
    end
    # rubocop:enable Naming/PredicateMethod

    def load_definitions!
      DEFINITION_FILES.each { |path| require path }
    end
  end
end