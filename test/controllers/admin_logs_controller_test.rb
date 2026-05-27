# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "../test_helper"
require_relative "../dummy/config/environment"

require "devise/test/integration_helpers"
require "rails/test_help"

class AdminLogsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  TEST_PASSWORD = "AdminLogsPassword!2026"

  setup do
    @original_admin_dashboard_path_resolver = RecordingStudioApi.configuration.admin_dashboard_path_resolver
    @original_admin_logs_path_resolver = RecordingStudioApi.configuration.admin_logs_path_resolver
    RecordingStudioApi.configuration.admin_dashboard_path_resolver = ->(controller:, **) { controller.main_app.admin_api_path }
    RecordingStudioApi.configuration.admin_logs_path_resolver = lambda do |controller:, **params|
      controller.main_app.admin_api_logs_path(params)
    end

    @user = User.create!(email: "admin-logs-#{SecureRandom.hex(4)}@example.com") do |user|
      user.password = TEST_PASSWORD
      user.password_confirmation = TEST_PASSWORD
    end

    sign_in @user

    @admin_root = RecordingStudioAdmin::Admin.create!(name: "Admin", key: SecureRandom.hex(4))
    @admin_root_recording = RecordingStudio::Recording.create!(recordable: @admin_root)
    admin_access = RecordingStudio::Access.create!(actor: @user, role: :admin)
    RecordingStudio::Recording.create!(recordable: admin_access, parent_recording: @admin_root_recording)

    ensure_api_request_logs_table!

    RecordingStudioApi::ApiRequestLog.delete_all
    30.times do |index|
      RecordingStudioApi::ApiRequestLog.create!(
        occurred_at: Time.current - index.minutes,
        request_id: "req-#{index}",
        request_method: index.even? ? "GET" : "POST",
        request_path: "/recordings/#{index}",
        status_code: 200 + (index % 2),
        duration_ms: 100 + index
      )
    end
  end

  teardown do
    RecordingStudioApi.configuration.admin_dashboard_path_resolver = @original_admin_dashboard_path_resolver
    RecordingStudioApi.configuration.admin_logs_path_resolver = @original_admin_logs_path_resolver
  end

  test "renders the logs page with a lazy frame-targeted loader" do
    get admin_api_logs_path

    assert_response :success
    assert_includes response.body, "Back"
    assert_includes response.body, admin_api_path
    assert_includes response.body, "API logs"
    assert_includes response.body, "Request log entries recorded by the API logging database."
    assert_includes response.body, "Occurred"
    assert_includes response.body, "Request ID"
    assert_includes response.body, "req-0"
    assert_includes response.body, "admin_api_logs_content"
    assert_includes response.body, 'data-controller="auto-load"'
    assert_includes response.body, "Loading more logs..."
    assert_includes response.body, "page=2"
  end

  test "frame request replaces the logs content with additional rows" do
    get admin_api_logs_path(page: 2), headers: { "Turbo-Frame" => "admin_api_logs_content" }

    assert_response :success
    assert_equal Mime[:html].to_s, response.media_type
    assert_includes response.body, '<turbo-frame id="admin_api_logs_content">'
    assert_includes response.body, "req-29"
  end

  test "turbo stream requests redirect back to html logs page" do
    get admin_api_logs_path(format: :turbo_stream), params: { page: 2 }

    assert_response :see_other
    assert_redirected_to admin_api_logs_path(page: 2)
  end

  test "forbids the logs page when the current root is not admin" do
    workspace = Workspace.create!(name: "Workspace root")
    workspace_root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    workspace_access = RecordingStudio::Access.create!(actor: @user, role: :admin)
    RecordingStudio::Recording.create!(recordable: workspace_access, parent_recording: workspace_root_recording)

    patch recording_studio_root_switchable.root_switch_path(scope: "all_roots"), params: {
      root_switch: {
        root_recording_id: workspace_root_recording.id,
        return_to: admin_api_logs_path
      }
    }

    follow_redirect!

    assert_response :forbidden
  end

  test "renders the empty state when the logging table is missing" do
    connection = RecordingStudioApi::ApiRequestLog.connection
    table_name = RecordingStudioApi::ApiRequestLog.table_name
    connection.drop_table(table_name) if connection.table_exists?(table_name)

    get admin_api_logs_path

    assert_response :success
    assert_includes response.body, "No API logs yet"
    assert_includes response.body, "API request logging has not produced any rows yet."
  ensure
    ensure_api_request_logs_table!
  end

  private

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
      t.uuid :oauth_grant_session_id
      t.string :remote_ip
      t.string :user_agent
      t.string :error_class
      t.string :error_message
      t.jsonb :request_params, null: false, default: {}

      t.timestamps
    end
  end
end