# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "../test_helper"
require_relative "../dummy/config/environment"
require_relative "../support/api_dummy_helpers"

require "devise/test/integration_helpers"
require "rails/test_help"

class RecordingStudioAdminApiScreensTest < ActionDispatch::IntegrationTest
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

  test "renders user API access screens from a workspace root" do
    workspace_root_recording, access_recording = create_access_recording_for(
      user: @user,
      workspace_name: "API access workspace",
      role: :admin
    )
    payload = provision_api_client_for(access_recording: access_recording, name: "Workspace API key")
    api_client = payload.fetch(:api_client)
    rotation_result = RecordingStudioApi::Services::RotateApiCredential.call(api_client: api_client, actor: @user)

    assert rotation_result.success?
    rotated_credential = rotation_result.value.fetch(:credential)

    RecordingStudioApi::ApiRequestLog.create!(
      occurred_at: Time.current,
      request_id: "rs-admin-access-log-1",
      request_method: "GET",
      request_path: "/recording_studio_api/api/v1/workspaces",
      status_code: 200,
      duration_ms: 42,
      rate_limited: false,
      api_client_id: api_client.id,
      api_credential_id: rotated_credential.id,
      access_recording_id: access_recording.id,
      root_recording_id: workspace_root_recording.id,
      remote_ip: "10.20.0.1"
    )

    switch_to_root(workspace_root_recording)

    get "/api/sections/api"

    assert_response :success
    assert_includes response.body, "API"
    assert_includes response.body, "/api/screens/api_keys"
    assert_includes response.body, "/api/screens/api_requests"
    section_links = Nokogiri::HTML(response.body).css("a").select do |link|
      ["Create API key", "View API keys", "View requests"].include?(link.text.strip)
    end

    assert_equal(["Create API key", "View API keys", "View requests"], section_links.map { |link| link.text.strip })
    assert_includes section_links[0]["class"], "--button-primary-background-color"
    assert_includes section_links[1]["class"], "--button-default-background-color"

    get "/api/screens/api_keys"

    assert_response :success
    assert_includes response.body, 'data-recording-studio-default-layout="true"'
    refute_includes response.body, 'data-controller="flat-pack--sidebar-layout"'
    assert_includes response.body, "API keys"
    assert_includes response.body, "API keys for API access workspace"
    assert_select %(select[name="status"] option[value="active"][selected]), text: "Active", count: 1
    assert_select %(nav.flat-pack-page-nav a[href="/api"]), count: 1
    refute_includes response.body, "return_to=%2Fadmin"

    get "/recording_studio_api/api_clients/#{api_client.id}/edit", params: { close_url: "/api/screens/api_keys" }

    assert_response :success
    assert_includes response.body, 'data-recording-studio-default-layout="true"'
    refute_includes response.body, 'data-controller="flat-pack--sidebar-layout"'
    assert_includes response.body, "Edit API access"

    get "/api/screens/api_keys/table"

    assert_response :success
    assert_includes response.body, "Workspace API key"
    assert_includes response.body, rotated_credential.oauth_client_id
    assert_includes response.body, "Active"
    assert_includes response.body, "View requests"
    assert_includes response.body, "Rotate key"
    assert_includes response.body, "Revoke key"

    get "/api/screens/api_keys/table", params: { status: "revoked", columns: %w[name api_key access_point role status] }

    assert_response :success
    assert_includes response.body, payload.fetch(:credential).oauth_client_id
    assert_includes response.body, "Revoked"
    refute_includes response.body, rotated_credential.oauth_client_id

    get "/api/screens/api_requests/table", params: { api_credential_id: rotated_credential.id }

    assert_response :success
    assert_includes response.body, "/recording_studio_api/api/v1/workspaces"
    assert_includes response.body, "api_credential_id=#{rotated_credential.id}"
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

    get "/api/screens/api_requests", params: { api_client_id: api_client.id }

    assert_response :success
    refute_includes response.body, "Avg duration"
    refute_includes response.body, "Error rate"
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

    get "/api/screens/api_keys/table", params: {
      root_recording_id: first_root_recording.id,
      parent_recording_id: first_root_recording.id,
      include_children: "1"
    }

    assert_response :success
    assert_includes response.body, "First scoped key"
    assert_includes response.body, first_payload.fetch(:credential).oauth_client_id
    refute_includes response.body, "Second scoped key"
    refute_includes response.body, second_payload.fetch(:credential).oauth_client_id

    get "/api/screens/api_keys/table", params: {
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
    assert_includes response.body, "/api/screens/api_keys"
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