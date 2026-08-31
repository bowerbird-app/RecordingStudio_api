# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "../test_helper"
require_relative "../dummy/config/environment"
require_relative "../support/api_dummy_helpers"

require "devise/test/integration_helpers"
require "rails/test_help"

class AdminDashboardsControllerTest < ActionDispatch::IntegrationTest
  # rubocop:disable Metrics/BlockLength
  include Devise::Test::IntegrationHelpers
  include ApiDummyHelpers

  TEST_PASSWORD = "AdminDashboardPassword!2026"

  setup do
    configure_dummy_operations_api!
    @original_admin_dashboard_path_resolver = RecordingStudioApi.configuration.admin_dashboard_path_resolver
    @original_admin_settings_path_resolver = RecordingStudioApi.configuration.admin_settings_path_resolver
    @original_admin_rate_limiting_path_resolver = RecordingStudioApi.configuration.admin_rate_limiting_path_resolver
    @original_admin_requests_path_resolver = RecordingStudioApi.configuration.admin_requests_path_resolver
    @original_admin_errors_path_resolver = RecordingStudioApi.configuration.admin_errors_path_resolver
    @original_admin_logs_path_resolver = RecordingStudioApi.configuration.admin_logs_path_resolver
    RecordingStudioApi.configuration.admin_dashboard_path_resolver = ->(**) { admin_api_path }
    RecordingStudioApi.configuration.admin_settings_path_resolver = lambda do |**params|
      admin_api_settings_path(params.except(:controller))
    end
    RecordingStudioApi.configuration.admin_rate_limiting_path_resolver = lambda do |**params|
      admin_api_rate_limiting_path(params.except(:controller))
    end
    RecordingStudioApi.configuration.admin_requests_path_resolver = lambda do |**params|
      admin_api_requests_path(params.except(:controller))
    end
    RecordingStudioApi.configuration.admin_errors_path_resolver = lambda do |**params|
      admin_api_errors_path(params.except(:controller))
    end
    RecordingStudioApi.configuration.admin_logs_path_resolver = lambda do |**params|
      admin_api_logs_path(params.except(:controller))
    end

    @user = User.create!(email: "admin-dashboard-#{SecureRandom.hex(4)}@example.com") do |user|
      user.password = TEST_PASSWORD
      user.password_confirmation = TEST_PASSWORD
    end

    sign_in @user

    @admin_root, @admin_root_recording = create_admin_root_recording
    create_access_recording(parent_recording: @admin_root_recording, user: @user, role: :admin)

    @admin_api = RecordingStudioApi::AdminApi.find_or_create_by!(key: "api") do |record|
      record.name = "Admin API"
    end
    @admin_api_recording = RecordingStudio::Recording.unscoped.find_or_create_by!(
      recordable: @admin_api,
      root_recording_id: @admin_root_recording.id,
      parent_recording_id: @admin_root_recording.id
    )

    ensure_api_request_logs_table!
    RecordingStudioApi::ApiRequestLog.delete_all
    [1, 2, 2, 4, 7].each_with_index do |count, index|
      count.times do |occurrence|
        RecordingStudioApi::ApiRequestLog.create!(
          occurred_at: Time.current.beginning_of_hour - index.hours + occurrence.minutes,
          request_id: "dash-#{index}-#{occurrence}",
          request_method: "GET",
          request_path: "/admin/api",
          status_code: 200,
          duration_ms: 50
        )
      end
    end

    [3, 5].each_with_index do |count, index|
      day_offset = index.zero? ? 2 : 15

      count.times do |occurrence|
        RecordingStudioApi::ApiRequestLog.create!(
          occurred_at: Time.current.beginning_of_day - day_offset.days + occurrence.hours,
          request_id: "dash-day-#{index}-#{occurrence}",
          request_method: "GET",
          request_path: "/admin/api",
          status_code: 200,
          duration_ms: 50
        )
      end
    end

    4.times do |occurrence|
      RecordingStudioApi::ApiRequestLog.create!(
        occurred_at: Time.current.beginning_of_day - 35.days + occurrence.hours,
        request_id: "dash-outside-#{occurrence}",
        request_method: "GET",
        request_path: "/admin/api",
        status_code: 200,
        duration_ms: 50
      )
    end

    [2, 1].each_with_index do |count, index|
      day_offset = index.zero? ? 1 : 10

      count.times do |occurrence|
        RecordingStudioApi::ApiRequestLog.create!(
          occurred_at: Time.current.beginning_of_day - day_offset.days + occurrence.hours,
          request_id: "dash-rate-limited-#{index}-#{occurrence}",
          request_method: "GET",
          request_path: "/admin/api",
          status_code: 429,
          duration_ms: 50,
          rate_limited: true
        )
      end
    end

    RecordingStudioApi::ApiRequestLog.create!(
      occurred_at: Time.current.beginning_of_day - 45.days,
      request_id: "dash-rate-limited-outside",
      request_method: "GET",
      request_path: "/admin/api",
      status_code: 429,
      duration_ms: 50,
      rate_limited: true
    )

    [2, 1].each_with_index do |count, index|
      day_offset = index.zero? ? 3 : 12

      count.times do |occurrence|
        RecordingStudioApi::ApiRequestLog.create!(
          occurred_at: Time.current.beginning_of_day - day_offset.days + occurrence.hours,
          request_id: "dash-errors-#{index}-#{occurrence}",
          request_method: "GET",
          request_path: "/admin/api",
          status_code: 500,
          duration_ms: 50
        )
      end
    end

    RecordingStudioApi::ApiRequestLog.create!(
      occurred_at: Time.current.beginning_of_day - 50.days,
      request_id: "dash-errors-outside",
      request_method: "GET",
      request_path: "/admin/api",
      status_code: 500,
      duration_ms: 50
    )

    RecordingStudioApi::ApiRequestLog.create!(
      occurred_at: Time.current.beginning_of_day - 6.days,
      request_id: "dash-errors-auth",
      request_method: "GET",
      request_path: "/admin/api",
      status_code: 403,
      duration_ms: 50,
      error_class: "RecordingStudioApi::AuthorizationError",
      error_message: "Admin API is not available for the current actor"
    )

    RecordingStudioApi::ApiRequestLog.create!(
      occurred_at: Time.current.beginning_of_day - 4.days,
      request_id: "dash-errors-generic",
      request_method: "GET",
      request_path: "/admin/api",
      status_code: 500,
      duration_ms: 50,
      error_class: "RecordingStudioApi::Error",
      error_message: "Unexpected API error"
    )

    RecordingStudioApi::ApiRequestLog.create!(
      occurred_at: Time.current.beginning_of_day - 3.days,
      request_id: "dash-errors-api-endpoint",
      request_method: "GET",
      controller_name: "recording_studio_api/api/recordings",
      request_path: "/api/v1/recordings",
      status_code: 500,
      duration_ms: 50,
      error_class: "RecordingStudioApi::ExternalEndpointError",
      error_message: "Error from non-admin API endpoint"
    )
  end

  teardown do
    RecordingStudioApi.configuration.admin_dashboard_path_resolver = @original_admin_dashboard_path_resolver
    RecordingStudioApi.configuration.admin_settings_path_resolver = @original_admin_settings_path_resolver
    RecordingStudioApi.configuration.admin_rate_limiting_path_resolver = @original_admin_rate_limiting_path_resolver
    RecordingStudioApi.configuration.admin_requests_path_resolver = @original_admin_requests_path_resolver
    RecordingStudioApi.configuration.admin_errors_path_resolver = @original_admin_errors_path_resolver
    RecordingStudioApi.configuration.admin_logs_path_resolver = @original_admin_logs_path_resolver
  end

  test "renders the admin api dashboard from the configured host route" do
    get admin_api_dashboard_path

    assert_response :success
    assert_includes response.body, "Admin API"
    assert_includes response.body, "Manage API access"
    assert_includes response.body, "Settings"
    assert_includes response.body, "Rate limiting"
    assert_includes response.body, "Logs"
    assert_includes response.body, admin_api_settings_path
    assert_includes response.body, admin_api_rate_limiting_path
    assert_includes response.body, admin_api_logs_path
    assert_includes response.body, admin_api_requests_path
    assert_includes response.body, admin_api_errors_path
    assert_includes response.body, "Requests last 24 hours"
    assert_includes response.body, "Requests last 30 days"
    assert_includes response.body, "Rate limiting (last 30 days)"
    assert_includes response.body, "Rate-limited requests per day"
    assert_includes response.body, "Rate-limited requests"
    assert_includes response.body, "Errors (last 30 days)"
    assert_includes response.body, "Error requests per day"
    assert_includes response.body, "Error requests"
    assert_includes response.body, "Full screen"
    assert_includes response.body, "flat-pack--chart"
    assert_not_includes response.body, "Peak hour"
    assert_select %(turbo-frame#admin-api-requests-last-24-hours-frame[src*="/recording_studio_api/admin_api/requests"]), count: 1
    assert_select %(turbo-frame#admin-api-requests-last-24-hours-frame[src*="dashboard_embed=1"]), count: 1
    assert_select %(turbo-frame#admin-api-requests-last-24-hours-frame[src*="show_summary=1"]), count: 1
    assert_select %(turbo-frame#admin-api-requests-last-24-hours-frame[src*="range=last_24_hours"]), count: 1
    assert_select %(turbo-frame#admin-api-requests-last-24-hours-frame[src*="group_by=hour"]), count: 1
    assert_select %(turbo-frame#admin-api-requests-last-30-days-frame[src*="/recording_studio_api/admin_api/requests"]), count: 1
    assert_select %(turbo-frame#admin-api-requests-last-30-days-frame[src*="dashboard_embed=1"]), count: 1
    assert_select %(a[href="#{admin_api_settings_path(close_url: admin_api_dashboard_path)}"]), text: "Settings", count: 1
    assert_select %(a[href="#{admin_api_rate_limiting_path(close_url: admin_api_dashboard_path)}"]), text: "Rate limiting", count: 1
    assert_select %(a[href="#{admin_api_logs_path(close_url: admin_api_dashboard_path)}"]), text: "Logs", count: 1
    assert_select %(a[href="#{admin_api_requests_path(close_url: admin_api_dashboard_path, range: 'last_24_hours', group_by: 'hour')}"]), text: "Full screen", count: 1
    assert_select %(a[href="#{admin_api_requests_path(close_url: admin_api_dashboard_path, start_date: 29.days.ago.to_date.iso8601, end_date: Date.current.iso8601, group_by: 'day')}"]), text: "Full screen", count: 1
    assert_select %(a[href="#{admin_api_errors_path(close_url: admin_api_dashboard_path, start_date: 29.days.ago.to_date.iso8601, end_date: Date.current.iso8601)}"]), text: "Full screen", count: 1
    assert_not_includes response.body, "Admin API views start here"
    assert_not_includes response.body, "Section key"
  end

  test "renders the dedicated admin api errors page with filters" do
    get admin_api_errors_path

    assert_response :success
    assert_includes response.body, "Admin API errors"
    assert_includes response.body, "Filter and inspect admin API error volume."
    assert_includes response.body, "admin-api-errors-chart-frame"
    assert_includes response.body, "flat-pack--auto-submit"
    assert_includes response.body, "Date Range"
    assert_includes response.body, "Error type"
    assert_includes response.body, "All error types"
    assert_includes response.body, "No exception captured"
    assert_includes response.body, "RecordingStudioApi::AuthorizationError"
    assert_select %(a[href="#{admin_api_path}"]), minimum: 1
  end

  test "falls back to all api errors when no admin scoped errors are available" do
    RecordingStudioApi::ApiRequestLog.where("controller_name LIKE ?", "recording_studio_api/admin_%").delete_all
    RecordingStudioApi::ApiRequestLog.where("request_path LIKE ? OR request_path LIKE ?", "/admin/api%", "/recording_studio_api/admin_api%").delete_all

    get admin_api_errors_path

    assert_response :success
    assert_includes response.body, "RecordingStudioApi::ExternalEndpointError"
  end

  test "frame request updates only the dedicated admin errors chart frame" do
    get admin_api_errors_path(error_type: "RecordingStudioApi::AuthorizationError"), headers: { "Turbo-Frame" => "admin-api-errors-chart-frame" }

    assert_response :success
    assert_equal Mime[:html].to_s, response.media_type
    assert_includes response.body, '<turbo-frame id="admin-api-errors-chart-frame">'
    assert_includes response.body, "RecordingStudioApi::AuthorizationError"
  end

  test "renders the dedicated admin api requests page with filters" do
    get admin_api_requests_path

    assert_response :success
    assert_includes response.body, "Admin API requests"
    assert_includes response.body, "Filter and inspect admin API request volume."
    assert_includes response.body, "admin-api-requests-chart-frame"
    assert_includes response.body, "flat-pack--auto-submit"
    assert_includes response.body, "All statuses"
    assert_includes response.body, "Success (2xx)"
    assert_includes response.body, "Client errors (4xx)"
    assert_includes response.body, "Server errors (5xx)"
    assert_select %(select[name="group_by"]), count: 1
    assert_includes response.body, "Hour"
    assert_includes response.body, "Day"
    assert_includes response.body, "Week"
    assert_includes response.body, "Month"
    assert_includes response.body, "Year"
    assert_includes response.body, "Occurred"
    assert_includes response.body, "Method"
    assert_includes response.body, "Path"
    assert_includes response.body, "Status"
    assert_includes response.body, "Rate limited"
    assert_includes response.body, "IP address"
    assert_includes response.body, "Duration"
    assert_select %(a[href="#{admin_api_path}"]), minimum: 1
  end

  test "requests filter form preserves close url when opened from dashboard" do
    get admin_api_requests_path(close_url: admin_api_path)

    assert_response :success
    assert_includes response.body, "close_url=%2Fadmin%2Fapi"
  end

  test "dashboard frame request renders compact requests chart from admin requests controller" do
    get admin_api_requests_path(
      dashboard_embed: "1",
      show_summary: "1",
      close_url: admin_api_path,
      range: "last_24_hours",
      group_by: "hour"
    ), headers: { "Turbo-Frame" => "admin-api-requests-last-24-hours-frame" }

    assert_response :success
    assert_equal Mime[:html].to_s, response.media_type
    assert_includes response.body, '<turbo-frame id="admin-api-requests-last-24-hours-frame">'
    assert_includes response.body, "flat-pack--chart"
    assert_not_includes response.body, "Total requests"
    assert_not_includes response.body, "Difference"
    assert_not_includes response.body, "All statuses"
  end

  test "frame request updates only the dedicated admin requests chart frame" do
    get admin_api_requests_path(status: "server_error", group_by: "hour"), headers: { "Turbo-Frame" => "admin-api-requests-chart-frame" }

    assert_response :success
    assert_equal Mime[:html].to_s, response.media_type
    assert_includes response.body, '<turbo-frame id="admin-api-requests-chart-frame">'
    assert_select %(select[name="group_by"]), count: 1
    assert_select %(select[name="group_by"] option[value="hour"][selected]), text: "Hour", count: 1
    hour_index = response.body.index('option value="hour"')
    day_index = response.body.index('option value="day"')
    week_index = response.body.index('option value="week"')
    month_index = response.body.index('option value="month"')
    year_index = response.body.index('option value="year"')

    assert_not_nil hour_index
    assert_not_nil day_index
    assert_not_nil week_index
    assert_not_nil month_index
    assert_not_nil year_index
    assert_operator hour_index, :<, day_index
    assert_operator day_index, :<, week_index
    assert_operator week_index, :<, month_index
    assert_operator month_index, :<, year_index
    assert_includes response.body, "Occurred"
  end

  test "creates the admin api section when it is missing for the current admin root" do
    admin_api_recordings = RecordingStudio::Recording.unscoped.where(
      parent_recording_id: @admin_root_recording.id,
      recordable_type: "RecordingStudioApi::AdminApi"
    )
    RecordingStudioApi::AdminApi.where(id: admin_api_recordings.select(:recordable_id)).delete_all
    admin_api_recordings.delete_all

    assert_nil RecordingStudio::Recording.unscoped.find_by(
      parent_recording_id: @admin_root_recording.id,
      recordable_type: "RecordingStudioApi::AdminApi"
    )

    get admin_api_dashboard_path

    assert_response :success

    created_recording = RecordingStudio::Recording.unscoped.find_by(
      parent_recording_id: @admin_root_recording.id,
      recordable_type: "RecordingStudioApi::AdminApi"
    )

    assert_not_nil created_recording
    assert_equal @admin_root_recording.id, created_recording.root_recording_id
    assert_equal "api", created_recording.recordable.key
  end

  test "renders the admin api settings page from the configured host route" do
    get admin_api_settings_path

    assert_response :success
    assert_includes response.body, 'data-recording-studio-default-layout="true"'
    assert_includes response.body, "Public API settings"
    assert_includes response.body, "Manage public API access and runtime operational overrides."
    assert_includes response.body, "Runtime overrides"
    assert_includes response.body, "Effective configuration"
    assert_includes response.body, "Configured APIs"
    assert_includes response.body, "Public API versions"
    assert_includes response.body, "Operations API versions"
    assert_not_includes response.body, "Rate limit API enabled"
    assert_includes response.body, "API request logging enabled"
    assert_select %(a[href="#{admin_api_path}"]), minimum: 1
  end

  test "renders named API settings with the Recording Studio core layout" do
    get admin_api_settings_path(api_key: "operations")

    assert_response :success
    assert_includes response.body, 'data-recording-studio-default-layout="true"'
    assert_includes response.body, "Operations API settings"
  end

  test "allows an API administrator to update site-wide API access" do
    get admin_api_settings_path

    assert_response :success
    assert_select %(input[name="api_access[enabled]"][type="checkbox"]), count: 1
    assert_includes response.body, "Enable Public API access"

    patch recording_studio_api.admin_api_access_settings_path, params: {
      api_access: { enabled: "0" }
    }

    assert_redirected_to admin_api_settings_path(close_url: admin_api_path)
    assert_equal false, RecordingStudioApi::ApiSetting.find_by!(key: "api").api_access_enabled
  end

  test "allows an API administrator to set runtime policy overrides" do
    patch recording_studio_api.admin_api_runtime_policy_settings_path, params: {
      runtime_policy: {
        api_request_logging_enabled: "true",
        credential_ttl_seconds: "7200",
        access_token_ttl_seconds: "900",
        api_request_log_retention_days: "14",
        api_daily_metric_retention_days: "90"
      }
    }

    assert_redirected_to admin_api_settings_path(close_url: admin_api_path)
    setting = RecordingStudioApi::ApiSetting.find_by!(key: "api")
    assert_equal true, setting.runtime_overrides_hash.fetch("api_request_logging_enabled")
    assert_equal 7200, setting.runtime_overrides_hash.fetch("credential_ttl_seconds")
    assert_equal 14, setting.runtime_overrides_hash.fetch("api_request_log_retention_days")

    policy = RecordingStudioApi::ApiRuntimePolicy.for(:public)
    assert policy.api_request_logging_enabled
    assert_equal 7200, policy.credential_ttl.to_i
    assert_equal 14, policy.api_request_log_retention_days
  end

  test "allows an API administrator to set rate limit overrides" do
    patch recording_studio_api.admin_api_rate_limiting_settings_path, params: {
      rate_limit: {
        rate_limit_api_enabled: "true",
        rate_limit_api_read_requests: "50",
        rate_limit_api_read_period_seconds: "30"
      }
    }

    assert_redirected_to admin_api_rate_limiting_path(close_url: admin_api_path)
    policy = RecordingStudioApi::ApiRuntimePolicy.for(:public)
    assert policy.rate_limit_api_enabled
    assert_equal 50, policy.rate_limit_api_read_requests
    assert_equal 30, policy.rate_limit_api_read_period_seconds
  end

  test "renders the admin api rate limiting page from the configured host route" do
    get admin_api_rate_limiting_path

    assert_response :success
    assert_includes response.body, "Rate limiting"
    assert_includes response.body, "Override rate-limit enables and thresholds at runtime"
    assert_includes response.body, "Rate limit OAuth enabled"
    assert_includes response.body, "Rate limit API pre-auth enabled"
    assert_includes response.body, "Rate limit API enabled"
    assert_includes response.body, "Rate limit Redis namespace"
    assert_select %(a[href="#{admin_api_path}"]), minimum: 1
  end

  test "switching to a workspace root falls back to the host root when the admin dashboard path is requested" do
    workspace = Workspace.create!(name: "Workspace root")
    workspace_root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    create_access_recording(parent_recording: workspace_root_recording, user: @user, role: :admin)

    patch recording_studio_root_switchable.root_switch_path(scope: "all_roots"), params: {
      root_switch: {
        root_recording_id: workspace_root_recording.id,
        return_to: admin_api_path
      }
    }

    assert_redirected_to "/"

    follow_redirect!

    assert_response :success
    assert_select "h1", text: "Recording Studio API demo"
  end

  # rubocop:enable Metrics/BlockLength

  test "forbids the dashboard when accessed directly from a non-admin root" do
    workspace = Workspace.create!(name: "Workspace root")
    workspace_root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    create_access_recording(parent_recording: workspace_root_recording, user: @user, role: :admin)

    patch recording_studio_root_switchable.root_switch_path(scope: "all_roots"), params: {
      root_switch: {
        root_recording_id: workspace_root_recording.id,
        return_to: root_path
      }
    }

    get admin_api_dashboard_path

    assert_response :forbidden
  end

  private

  def admin_api_path
    "/admin/api"
  end

  def admin_api_dashboard_path(params = {})
    path_with_query("/recording_studio_api/admin_api", params)
  end

  def admin_api_settings_path(params = {})
    path_with_query("/recording_studio_api/admin_api/settings", params)
  end

  def admin_api_rate_limiting_path(params = {})
    path_with_query("/recording_studio_api/admin_api/rate_limiting", params)
  end

  def admin_api_requests_path(params = {})
    path_with_query("/recording_studio_api/admin_api/requests", params)
  end

  def admin_api_errors_path(params = {})
    path_with_query("/recording_studio_api/admin_api/errors", params)
  end

  def admin_api_logs_path(params = {})
    path_with_query("/recording_studio_api/admin_api/logs", params)
  end

  def path_with_query(path, params)
    query = params.compact.to_query
    query.present? ? "#{path}?#{query}" : path
  end

  def create_access_recording(parent_recording:, user:, role:)
    grant_or_bootstrap_access!(recording: parent_recording, actor: user, role: role)
  end

  def ensure_api_request_logs_table!
    connection = RecordingStudioApi::ApiRequestLog.connection
    table_name = RecordingStudioApi::ApiRequestLog.table_name
    return if connection.table_exists?(table_name)

    connection.create_table table_name, id: :uuid do |t|
      t.datetime :occurred_at, null: false
      t.string :request_id
      t.string :request_method, null: false
      t.string :request_path, null: false
      t.string :route_name
      t.string :controller_name
      t.string :action_name
      t.integer :status_code, null: false
      t.integer :duration_ms, null: false
      t.boolean :rate_limited, null: false, default: false
      t.uuid :api_client_id
      t.uuid :api_credential_id
      t.uuid :access_recording_id
      t.uuid :root_recording_id
      t.string :remote_ip
      t.string :user_agent
      t.string :error_class
      t.string :error_message
      t.jsonb :request_params, null: false, default: {}

      t.timestamps
    end
  end
end