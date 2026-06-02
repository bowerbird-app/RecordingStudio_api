# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "../test_helper"
require_relative "../dummy/config/environment"

require "devise/test/integration_helpers"
require "rails/test_help"

class AdminDashboardsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  TEST_PASSWORD = "AdminDashboardPassword!2026"

  setup do
    @original_admin_dashboard_path_resolver = RecordingStudioApi.configuration.admin_dashboard_path_resolver
    @original_admin_logs_path_resolver = RecordingStudioApi.configuration.admin_logs_path_resolver
    RecordingStudioApi.configuration.admin_dashboard_path_resolver = ->(controller:, **) { controller.main_app.admin_api_path }
    RecordingStudioApi.configuration.admin_logs_path_resolver = lambda do |controller:, **params|
      controller.main_app.admin_api_logs_path(params)
    end

    @user = User.create!(email: "admin-dashboard-#{SecureRandom.hex(4)}@example.com") do |user|
      user.password = TEST_PASSWORD
      user.password_confirmation = TEST_PASSWORD
    end

    sign_in @user

    @admin_root = RecordingStudioAdmin::Admin.create!(name: "Admin", key: SecureRandom.hex(4))
    @admin_root_recording = RecordingStudio::Recording.create!(recordable: @admin_root)
    admin_access = RecordingStudio::Access.create!(actor: @user, role: :admin)
    RecordingStudio::Recording.create!(recordable: admin_access, parent_recording: @admin_root_recording)

    @admin_api = RecordingStudioApi::AdminApi.create!(key: "api-#{SecureRandom.hex(4)}", name: "Admin API")
    @admin_api_recording = RecordingStudio::Recording.create!(recordable: @admin_api, parent_recording: @admin_root_recording)

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
  end

  teardown do
    RecordingStudioApi.configuration.admin_dashboard_path_resolver = @original_admin_dashboard_path_resolver
    RecordingStudioApi.configuration.admin_logs_path_resolver = @original_admin_logs_path_resolver
  end

  test "renders the admin api dashboard from the configured host route" do
    get "/admin/api"

    assert_response :success
    assert_includes response.body, "Admin API"
    assert_includes response.body, "Gem-provided starting point for admin API tooling under the current admin root."
    assert_includes response.body, "Logs"
    assert_includes response.body, admin_api_logs_path
    assert_includes response.body, "API logs over time"
    assert_includes response.body, "Hourly request volume across the last 24 hours."
    assert_includes response.body, "Last 24 hours"
    assert_includes response.body, "Open full log view"
    assert_includes response.body, "API log volume over the last 24 hours"
    assert_select %(a[href="#{admin_api_logs_path(close_url: admin_api_path)}"]), text: "Logs", count: 1
    assert_select %(a[href="#{admin_api_logs_path(close_url: admin_api_path)}"]), text: "Open full log view", count: 1
    assert_not_includes response.body, "Admin API views start here"
    assert_not_includes response.body, "Section key"
  end

  test "creates the admin api section when it is missing for the current admin root" do
    RecordingStudio::Recording.unscoped.where(id: @admin_api_recording.id).delete_all
    RecordingStudioApi::AdminApi.where(id: @admin_api.id).delete_all

    assert_nil RecordingStudio::Recording.unscoped.find_by(
      parent_recording_id: @admin_root_recording.id,
      recordable_type: "RecordingStudioApi::AdminApi"
    )

    get "/admin/api"

    assert_response :success

    created_recording = RecordingStudio::Recording.unscoped.find_by(
      parent_recording_id: @admin_root_recording.id,
      recordable_type: "RecordingStudioApi::AdminApi"
    )

    assert_not_nil created_recording
    assert_equal @admin_root_recording.id, created_recording.root_recording_id
    assert_equal "api", created_recording.recordable.key
  end

  test "switching to a workspace root falls back to the host root when the admin dashboard path is requested" do
    workspace = Workspace.create!(name: "Workspace root")
    workspace_root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    workspace_access = RecordingStudio::Access.create!(actor: @user, role: :admin)
    RecordingStudio::Recording.create!(recordable: workspace_access, parent_recording: workspace_root_recording)

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

  test "forbids the dashboard when accessed directly from a non-admin root" do
    workspace = Workspace.create!(name: "Workspace root")
    workspace_root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    workspace_access = RecordingStudio::Access.create!(actor: @user, role: :admin)
    RecordingStudio::Recording.create!(recordable: workspace_access, parent_recording: workspace_root_recording)

    patch recording_studio_root_switchable.root_switch_path(scope: "all_roots"), params: {
      root_switch: {
        root_recording_id: workspace_root_recording.id,
        return_to: root_path
      }
    }

    get "/admin/api"

    assert_response :forbidden
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