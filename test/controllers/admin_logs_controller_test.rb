# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "../test_helper"
require_relative "../dummy/config/environment"
require_relative "../support/api_dummy_helpers"

require "devise/test/integration_helpers"
require "rails/test_help"

class AdminLogsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ApiDummyHelpers

  TEST_PASSWORD = "AdminLogsPassword!2026"

  setup do
    @original_admin_dashboard_path_resolver = RecordingStudioApi.configuration.admin_dashboard_path_resolver
    @original_admin_logs_path_resolver = RecordingStudioApi.configuration.admin_logs_path_resolver
    RecordingStudioApi.configuration.admin_dashboard_path_resolver = ->(**) { admin_api_path }
    RecordingStudioApi.configuration.admin_logs_path_resolver = lambda do |**params|
      admin_api_logs_path(params.except(:controller))
    end

    @user = User.create!(email: "admin-logs-#{SecureRandom.hex(4)}@example.com") do |user|
      user.password = TEST_PASSWORD
      user.password_confirmation = TEST_PASSWORD
    end

    sign_in @user

    @admin_root, @admin_root_recording = create_admin_root_recording
    create_access_recording(parent_recording: @admin_root_recording, user: @user, role: :admin)

    ensure_api_request_logs_table!

    RecordingStudioApi::ApiRequestLog.delete_all
    30.times do |index|
      RecordingStudioApi::ApiRequestLog.create!(
        occurred_at: Time.current - index.minutes,
        request_id: "req-#{index}",
        request_method: index.even? ? "GET" : "POST",
        request_path: "/recordings/#{index}",
        status_code: 200 + (index % 2),
        duration_ms: 100 + index,
        rate_limited: index.zero?,
        remote_ip: "10.0.0.#{index + 1}"
      )
    end
  end

  teardown do
    RecordingStudioApi.configuration.admin_dashboard_path_resolver = @original_admin_dashboard_path_resolver
    RecordingStudioApi.configuration.admin_logs_path_resolver = @original_admin_logs_path_resolver
  end

  test "renders the logs page with a lazy frame-targeted loader" do
    without_admin_v1_logs_screen do
      get admin_api_logs_path

      assert_response :success
      assert_select %(a[href="#{admin_api_path}"]), minimum: 1
      assert_includes response.body, "API logs"
      assert_includes response.body, "Request log entries recorded by the API logging database."
      assert_includes response.body, "Occurred"
      assert_includes response.body, "Rate limited"
      assert_includes response.body, "IP address"
      assert_includes response.body, "10.0.0.1"
      assert_includes response.body, 'aria-label="Rate limited"'
      assert_includes response.body, 'data-controller="flat-pack--tooltip"'
      assert_includes response.body, "/recordings/1"
      assert_includes response.body, "/recordings/:id"
      assert_includes response.body, "sortable_table"
      assert_includes response.body, 'data-controller="auto-load"'
      assert_includes response.body, "Loading more logs..."
      assert_includes response.body, "page=2"
      assert_includes response.body, "sort=request_method"
      assert_includes response.body, 'data-turbo-frame="sortable_table"'
      assert_includes response.body, "Date Range"
      assert_includes response.body, "admin-logs-date-range-submit"
      assert_includes response.body, "click-&gt;admin-logs-date-range-submit#submitOnApply"
    end
  end

  test "renders legacy logs route directly" do
    get admin_api_logs_path

    assert_response :success
    assert_includes response.body, "API logs"
  end

  test "filters logs by date range and preserves date params in pagination links" do
    old_log = RecordingStudioApi::ApiRequestLog.create!(
      occurred_at: 10.days.ago,
      request_id: "req-old",
      request_method: "GET",
      request_path: "/recordings/old",
      status_code: 200,
      duration_ms: 90,
      rate_limited: false,
      remote_ip: "10.99.0.1"
    )

    recent_log = RecordingStudioApi::ApiRequestLog.create!(
      occurred_at: Time.current,
      request_id: "req-recent",
      request_method: "GET",
      request_path: "/recordings/recent",
      status_code: 200,
      duration_ms: 80,
      rate_limited: false,
      remote_ip: "10.99.0.2"
    )

    without_admin_v1_logs_screen do
      get admin_api_logs_path(start_date: Date.current.iso8601, end_date: Date.current.iso8601)

      assert_response :success
      assert_includes response.body, recent_log.remote_ip
      assert_not_includes response.body, old_log.remote_ip
      assert_includes response.body, "start_date=#{Date.current.iso8601}"
      assert_includes response.body, "end_date=#{Date.current.iso8601}"
    end
  end

  test "frame request replaces the logs content with additional rows" do
    without_admin_v1_logs_screen do
      get admin_api_logs_path(page: 2), headers: { "Turbo-Frame" => "sortable_table" }

      assert_response :success
      assert_equal Mime[:html].to_s, response.media_type
      assert_includes response.body, '<turbo-frame id="sortable_table">'
      assert_includes response.body, "10.0.0.30"
    end
  end

  test "supports sortable headers and applies sorting to loaded rows" do
    without_admin_v1_logs_screen do
      get admin_api_logs_path(sort: "duration_ms", direction: "desc")

      assert_response :success
      assert_includes response.body, "sort=duration_ms"
      assert_includes response.body, "direction=asc"
      assert_includes response.body, "page=2"
      assert_includes response.body, "direction=desc"

      first_row_position = response.body.index("10.0.0.30")
      last_row_position = response.body.index("10.0.0.6")

      refute_nil first_row_position
      refute_nil last_row_position
      assert_operator first_row_position, :<, last_row_position
    end
  end

  test "turbo stream requests redirect back to html logs page" do
    without_admin_v1_logs_screen do
      get admin_api_logs_path(format: :turbo_stream), params: { page: 2 }

      assert_response :see_other
      assert_redirected_to admin_api_logs_path(page: 2, sort: "occurred_at", direction: "desc")
    end
  end

  test "switching to a workspace root preserves the configured legacy logs path" do
    workspace = Workspace.create!(name: "Workspace root")
    workspace_root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    create_access_recording(parent_recording: workspace_root_recording, user: @user, role: :admin)

    patch recording_studio_root_switchable.root_switch_path(scope: "all_roots"), params: {
      root_switch: {
        root_recording_id: workspace_root_recording.id,
        return_to: admin_api_logs_path
      }
    }

    assert_redirected_to admin_api_logs_path

    follow_redirect!

    assert_response :forbidden
  end

  test "forbids the logs page when accessed directly from a non-admin root" do
    workspace = Workspace.create!(name: "Workspace root")
    workspace_root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    create_access_recording(parent_recording: workspace_root_recording, user: @user, role: :admin)

    patch recording_studio_root_switchable.root_switch_path(scope: "all_roots"), params: {
      root_switch: {
        root_recording_id: workspace_root_recording.id,
        return_to: root_path
      }
    }

    without_admin_v1_logs_screen do
      get admin_api_logs_path

      assert_response :forbidden
    end
  end

  test "renders the empty state when the logging table is missing" do
    connection = RecordingStudioApi::ApiRequestLog.connection
    table_name = RecordingStudioApi::ApiRequestLog.table_name
    connection.drop_table(table_name) if connection.table_exists?(table_name)

    without_admin_v1_logs_screen do
      get admin_api_logs_path

      assert_response :success
      assert_includes response.body, "No API logs yet"
      assert_includes response.body, "API request logging has not produced any rows yet."
    end
  ensure
    ensure_api_request_logs_table!
  end

  private

  def admin_api_path
    "/admin/api"
  end

  def admin_api_logs_path(params = {})
    path_with_query("/recording_studio_api/admin_api/logs", params)
  end

  def path_with_query(path, params)
    query = params.compact.to_query
    query.present? ? "#{path}?#{query}" : path
  end

  def create_access_recording(parent_recording:, user:, role:)
    with_access_creation_context do
      access = RecordingStudio::Access.create!(actor: user, role: role)
      RecordingStudio::Recording.create!(recordable: access, parent_recording: parent_recording)
    end
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

  def without_admin_v1_logs_screen(&)
    RecordingStudioApi::Admin.stub(:available?, false, &)
  end
end