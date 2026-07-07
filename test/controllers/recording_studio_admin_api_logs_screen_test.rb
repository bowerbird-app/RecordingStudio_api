# frozen_string_literal: true
# rubocop:disable Metrics/BlockLength


ENV["RAILS_ENV"] = "test"
require_relative "../test_helper"
require_relative "../dummy/config/environment"
require_relative "../support/api_dummy_helpers"

require "devise/test/integration_helpers"
require "rails/test_help"

class RecordingStudioAdminApiLogsScreenTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ApiDummyHelpers

  TEST_PASSWORD = "AdminApiLogsPassword!2026"

  setup do
    ensure_admin_root_tables!

    @user = User.create!(email: "rs-admin-api-logs-#{SecureRandom.hex(4)}@example.com") do |user|
      user.password = TEST_PASSWORD
      user.password_confirmation = TEST_PASSWORD
    end

    sign_in @user
    @admin_root = AdminRoot.find_or_create_by!(name: "Admin")
    @admin_root_recording = RecordingStudio::Recording.find_or_create_by!(recordable: @admin_root)
    create_access_recording(parent_recording: @admin_root_recording, user: @user, role: :admin)

    ensure_api_request_logs_table!
    RecordingStudioApi::ApiRequestLog.delete_all
    RecordingStudioApi::ApiRequestLog.create!(
      occurred_at: Time.current,
      request_id: "rs-admin-log-1",
      request_method: "GET",
      request_path: "/recording_studio_api/api/v1/pages",
      status_code: 429,
      duration_ms: 123,
      rate_limited: true,
      remote_ip: "10.10.0.1"
    )
  end

  test "renders API logs through RecordingStudioAdmin screen" do
    get "/admin/screens/api_logs"

    assert_response :success
    assert_includes response.body, "API logs"
    assert_includes response.body, "Request log entries recorded by the API logging database."
    assert_includes response.body, "/admin/screens/api_logs/table"

    get "/admin/screens/api_logs/table"

    assert_response :success
    assert_includes response.body, "/recording_studio_api/api/v1/pages"
    assert_includes response.body, "429"
    assert_includes response.body, "10.10.0.1"
  end

  test "API logs widgets render semantic change colors" do
    RecordingStudioApi::ApiRequestLog.delete_all

    2.times do |i|
      RecordingStudioApi::ApiRequestLog.create!(
        occurred_at: i.days.ago,
        request_id: "rs-api-logs-current-#{i}",
        request_method: "GET",
        request_path: "/recording_studio_api/api/v1/pages",
        status_code: 200,
        duration_ms: 120,
        rate_limited: i.zero?,
        remote_ip: "10.11.0.1"
      )
    end

    4.times do |i|
      RecordingStudioApi::ApiRequestLog.create!(
        occurred_at: 40.days.ago - i.hours,
        request_id: "rs-api-logs-previous-#{i}",
        request_method: "GET",
        request_path: "/recording_studio_api/api/v1/pages",
        status_code: 200,
        duration_ms: 120,
        rate_limited: i < 3,
        remote_ip: "10.11.0.2"
      )
    end

    get "/admin/screens/api_logs/widgets/api_logs.widgets.total_requests"

    assert_response :success
    assert_includes response.body, "-50%"
    assert_includes response.body, "text-[var(--color-danger-background-color)]"

    get "/admin/screens/api_logs/widgets/api_logs.widgets.rate_limited_requests"

    assert_response :success
    assert_includes response.body, "-67%"
    assert_includes response.body, "text-[var(--color-success-background-color)]"
  end

  test "renders API Admin section with logs link and widgets" do
    get "/admin/sections/api_admin"

    assert_response :success
    assert_includes response.body, "API Admin"
    assert_includes response.body, "View logs"
    assert_includes response.body, "/admin/screens/api_logs"
    assert_includes response.body, "API requests"
    assert_includes response.body, "Rate limited"
  end

  test "admin widgets define change_good_when explicitly" do
    [
      RecordingStudioApi::Admin::ApiLogsScreen,
      RecordingStudioApi::Admin::ApiAccessRequestsScreen
    ].each do |screen_class|
      screen_class.widgets.each_value do |widget|
        assert widget.change_good_when.present?, "#{widget.key} is missing change_good_when"
      end
    end
  end

  test "renders user API access screens from a workspace root" do
    workspace_root_recording, access_recording = create_access_recording_for(
      user: @user,
      workspace_name: "API access workspace",
      role: :admin
    )
    payload = provision_api_client_for(access_recording: access_recording, name: "Workspace API key")
    api_client = payload.fetch(:api_client)

    RecordingStudioApi::ApiRequestLog.create!(
      occurred_at: Time.current,
      request_id: "rs-admin-access-log-1",
      request_method: "GET",
      request_path: "/recording_studio_api/api/v1/workspaces",
      status_code: 200,
      duration_ms: 42,
      rate_limited: false,
      api_client_id: api_client.id,
      api_credential_id: payload.fetch(:credential).id,
      access_recording_id: access_recording.id,
      root_recording_id: workspace_root_recording.id,
      remote_ip: "10.20.0.1"
    )

    switch_to_root(workspace_root_recording)

    get "/api/dashboard/sections/api"

    assert_response :success
    assert_includes response.body, "API"
    assert_includes response.body, "/api/dashboard/screens/api_access_clients"
    assert_includes response.body, "/api/dashboard/screens/api_access_requests"
    assert_includes response.body, "/api/dashboard/sections/api/widgets/api_access_requests.widgets.total_requests"
    assert_includes response.body, "widget_view_variant=card"
    refute_includes response.body, "widget_view_variant=compact"
    section_links = Nokogiri::HTML(response.body).css("a").select do |link|
      ["Create API key", "View API keys", "View requests"].include?(link.text.strip)
    end

    assert_equal(["Create API key", "View API keys", "View requests"], section_links.map { |link| link.text.strip })
    assert_includes section_links[0]["class"], "--button-primary-background-color"
    assert_includes section_links[1]["class"], "--button-default-background-color"

    get "/api/dashboard/sections/api/widgets/api_access_requests.widgets.total_requests",
        params: { widget_view_variant: "card" }

    assert_response :success
    assert_includes response.body, "API requests"
    assert_includes response.body, "text-5xl"
    refute_includes response.body, "min-h-28 max-h-28"
    refute_includes response.body, "text-4xl"

    get "/api/dashboard/screens/api_access_clients"

    assert_response :success
    assert_includes response.body, 'data-recording-studio-default-layout="true"'
    refute_includes response.body, 'data-controller="flat-pack--sidebar-layout"'
    assert_includes response.body, "API keys"
    assert_includes response.body, "API keys for API access workspace"
    assert_select %(nav.flat-pack-page-nav a[href="/api/dashboard"]), count: 1
    refute_includes response.body, "return_to=%2Fadmin"

    get "/recording_studio_api/api_clients/#{api_client.id}/edit", params: { close_url: "/api/dashboard/screens/api_access_clients" }

    assert_response :success
    assert_includes response.body, 'data-recording-studio-default-layout="true"'
    refute_includes response.body, 'data-controller="flat-pack--sidebar-layout"'
    assert_includes response.body, "Edit API access"

    get "/api/dashboard/screens/api_access_clients/table"

    assert_response :success
    assert_includes response.body, "Workspace API key"
    assert_includes response.body, payload.fetch(:credential).oauth_client_id
    assert_includes response.body, "View requests"
    assert_includes response.body, "Rotate key"
    assert_includes response.body, "Revoke key"

    get "/api/dashboard/screens/api_access_requests/table", params: { api_client_id: api_client.id }

    assert_response :success
    assert_includes response.body, "/recording_studio_api/api/v1/workspaces"
    assert_includes response.body, api_client.id
  end

  test "API access requests screen shows chart and widgets for request analytics" do
    workspace_root_recording, access_recording = create_access_recording_for(
      user: @user,
      workspace_name: "Analytics workspace",
      role: :admin
    )
    payload = provision_api_client_for(access_recording: access_recording, name: "Analytics API key")
    api_client = payload.fetch(:api_client)

    2.times do |i|
      RecordingStudioApi::ApiRequestLog.create!(
        occurred_at: i.days.ago,
        request_id: "rs-analytics-#{i}",
        request_method: "GET",
        request_path: "/recording_studio_api/api/v1/pages",
        status_code: i.zero? ? 500 : 200,
        duration_ms: 50 + i,
        rate_limited: false,
        api_client_id: api_client.id,
        api_credential_id: payload.fetch(:credential).id,
        access_recording_id: access_recording.id,
        root_recording_id: workspace_root_recording.id,
        remote_ip: "10.30.0.1"
      )
    end

    4.times do |i|
      RecordingStudioApi::ApiRequestLog.create!(
        occurred_at: 8.days.ago - i.hours,
        request_id: "rs-analytics-prev-#{i}",
        request_method: "GET",
        request_path: "/recording_studio_api/api/v1/pages",
        status_code: i.zero? ? 500 : 200,
        duration_ms: 60 + i,
        rate_limited: false,
        api_client_id: api_client.id,
        api_credential_id: payload.fetch(:credential).id,
        access_recording_id: access_recording.id,
        root_recording_id: workspace_root_recording.id,
        remote_ip: "10.30.0.2"
      )
    end

    switch_to_root(workspace_root_recording)

    get "/api/dashboard/screens/api_access_requests", params: { api_client_id: api_client.id }

    assert_response :success

    get "/api/dashboard/screens/api_access_requests/widgets/api_access_requests.widgets.total_requests",
        params: { api_client_id: api_client.id }

    assert_response :success
    assert_includes response.body, "-50%"
    refute_includes response.body, "-50.0%"
    assert_includes response.body, "text-[var(--color-danger-background-color)]"

    get "/api/dashboard/screens/api_access_requests/widgets/api_access_requests.widgets.avg_duration",
        params: { api_client_id: api_client.id }

    assert_response :success
    assert_includes response.body, "<span class=\"text-5xl font-bold\">51</span>"
    assert_includes response.body, "-18%"
    refute_includes response.body, "-18.0%"
    assert_includes response.body, "This month"
    assert_includes response.body, "text-[var(--color-success-background-color)]"

    get "/api/dashboard/screens/api_access_requests/widgets/api_access_requests.widgets.error_rate",
        params: { api_client_id: api_client.id }

    assert_response :success
    assert_includes response.body, "+100%"
    refute_includes response.body, "+100.0%"
    assert_includes response.body, "text-[var(--color-danger-background-color)]"
  end

  test "API access clients screen scopes clients to the requested root" do
    first_root_recording, first_access_recording = create_access_recording_for(
      user: @user,
      workspace_name: "First API access workspace",
      role: :admin
    )
    second_root_recording, second_access_recording = create_access_recording_for(
      user: @user,
      workspace_name: "Second API access workspace",
      role: :admin
    )
    first_payload = provision_api_client_for(access_recording: first_access_recording, name: "First scoped key")
    second_payload = provision_api_client_for(access_recording: second_access_recording, name: "Second scoped key")
    switch_to_root(first_root_recording)

    get "/api/dashboard/screens/api_access_clients/table", params: {
      root_recording_id: first_root_recording.id,
      parent_recording_id: first_root_recording.id,
      include_children: "1"
    }

    assert_response :success
    assert_includes response.body, "First scoped key"
    assert_includes response.body, first_payload.fetch(:credential).oauth_client_id
    refute_includes response.body, "Second scoped key"
    refute_includes response.body, second_payload.fetch(:credential).oauth_client_id

    get "/api/dashboard/screens/api_access_clients/table", params: {
      root_recording_id: second_root_recording.id,
      parent_recording_id: second_root_recording.id,
      include_children: "1"
    }

    assert_response :success
    assert_includes response.body, "Second scoped key"
    assert_includes response.body, second_payload.fetch(:credential).oauth_client_id
    refute_includes response.body, "First scoped key"
    refute_includes response.body, first_payload.fetch(:credential).oauth_client_id
  end

  test "dummy home links API keys to RecordingStudioAdmin API access screen" do
    workspace_root_recording, access_recording = create_access_recording_for(
      user: @user,
      workspace_name: "Redirect workspace",
      role: :admin
    )
    provision_api_client_for(access_recording: access_recording, name: "Redirect API key")
    switch_to_root(workspace_root_recording)

    get "/"

    assert_response :success
    assert_includes response.body, "/api/dashboard/screens/api_access_clients"
    assert_includes response.body, "root_recording_id=#{workspace_root_recording.id}"
  end

  private

  def switch_to_root(root_recording)
    patch recording_studio_root_switchable.root_switch_path(scope: "all_roots"), params: {
      root_switch: {
        root_recording_id: root_recording.id,
        return_to: "/"
      }
    }
  end

  def ensure_admin_root_tables!
    connection = ActiveRecord::Base.connection

    unless connection.table_exists?(:admin_roots)
      connection.create_table :admin_roots, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
        t.string :name, null: false

        t.timestamps
      end
    end

    return if connection.table_exists?(:admin_sections)

    connection.create_table :admin_sections, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :key, null: false
      t.string :name, null: false

      t.timestamps
    end
    connection.add_index :admin_sections, :key, unique: true
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
end
# rubocop:enable Metrics/BlockLength