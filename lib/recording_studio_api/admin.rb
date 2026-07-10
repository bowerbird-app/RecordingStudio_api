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
      recording_studio_api/admin/queries/api_metrics_query
      recording_studio_api/admin/queries/api_access_clients_query
      recording_studio_api/admin/queries/admin_api_credentials_query
      recording_studio_api/admin/queries/admin_api_endpoint_failures_query
      recording_studio_api/admin/api_requests_last_four_weeks_widget
      recording_studio_api/admin/most_used_api_keys_widget
      recording_studio_api/admin/admin_api_requests_last_four_weeks_widget
      recording_studio_api/admin/admin_api_performance_screen
      recording_studio_api/admin/admin_api_failing_endpoints_screen
      recording_studio_api/admin/admin_api_latency_last_four_weeks_widget
      recording_studio_api/admin/admin_api_client_errors_last_four_weeks_widget
      recording_studio_api/admin/admin_api_server_errors_last_four_weeks_widget
      recording_studio_api/admin/admin_api_authorization_failures_last_four_weeks_widget
      recording_studio_api/admin/admin_api_top_failing_endpoints_last_four_weeks_widget
      recording_studio_api/admin/admin_api_rate_limited_requests_last_four_weeks_widget
      recording_studio_api/admin/api_section
      recording_studio_api/admin/admin_api_section
      recording_studio_api/admin/api_keys_screen
      recording_studio_api/admin/api_access_requests_screen
      recording_studio_api/admin/admin_api_requests_screen
      recording_studio_api/admin/admin_api_credentials_screen
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
      ::RecordingStudioAdmin.register_section(AdminApiSection)
      ::RecordingStudioAdmin.register_widget(ApiRequestsLastFourWeeksWidget::Definition)
      ::RecordingStudioAdmin.register_widget(MostUsedApiKeysWidget::Definition)
      ::RecordingStudioAdmin.register_widget(AdminApiRequestsLastFourWeeksWidget::Definition)
      ::RecordingStudioAdmin.register_widget(AdminApiLatencyLastFourWeeksWidget::Definition)
      ::RecordingStudioAdmin.register_widget(AdminApiClientErrorsLastFourWeeksWidget::Definition)
      ::RecordingStudioAdmin.register_widget(AdminApiServerErrorsLastFourWeeksWidget::Definition)
      ::RecordingStudioAdmin.register_widget(AdminApiAuthorizationFailuresLastFourWeeksWidget::Definition)
      ::RecordingStudioAdmin.register_widget(AdminApiTopFailingEndpointsLastFourWeeksWidget::Definition)
      ::RecordingStudioAdmin.register_widget(AdminApiRateLimitedRequestsLastFourWeeksWidget::Definition)
      ::RecordingStudioAdmin.register_screen(ApiKeysScreen)
      ::RecordingStudioAdmin.register_screen(ApiAccessRequestsScreen)
      ::RecordingStudioAdmin.register_screen(AdminApiRequestsScreen)
      ::RecordingStudioAdmin.register_screen(AdminApiCredentialsScreen)
      ::RecordingStudioAdmin.register_screen(AdminApiPerformanceScreen)
      ::RecordingStudioAdmin.register_screen(AdminApiFailingEndpointsScreen)
      true
    end
    # rubocop:enable Naming/PredicateMethod

    def load_definitions!
      DEFINITION_FILES.each { |path| require path }
    end
  end
end