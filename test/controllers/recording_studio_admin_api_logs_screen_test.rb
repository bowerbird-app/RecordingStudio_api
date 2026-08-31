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
    configure_dummy_operations_api!
    RecordingStudioApi::Admin::Queries::AdminApiCredentialsQuery.clear_cache!
    ensure_admin_root_tables!

    @user = User.create!(email: "rs-admin-api-logs-#{SecureRandom.hex(4)}@example.com") do |user|
      user.password = TEST_PASSWORD
      user.password_confirmation = TEST_PASSWORD
    end

    sign_in @user
    @admin_root = AdminRoot.find_or_create_by!(name: "Admin")
    @admin_root_recording = RecordingStudio::Recording.find_or_create_by!(recordable: @admin_root)
    create_access_recording(parent_recording: @admin_root_recording, user: @user, role: :admin)
    RecordingStudioApi::Admin::ApiAuthorization.recording_for(
      api: :public,
      root_recording: @admin_root_recording,
      create: true
    )

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
    popular_payload = provision_api_client_for(access_recording: access_recording, name: "Popular API key")
    popular_api_client = popular_payload.fetch(:api_client)
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

    3.times do |i|
      RecordingStudioApi::ApiRequestLog.create!(
        occurred_at: i.days.ago,
        request_id: "rs-admin-popular-log-#{i}",
        request_method: "GET",
        request_path: "/recording_studio_api/api/v1/popular-workspaces",
        status_code: 200,
        duration_ms: 45,
        rate_limited: false,
        api_client_id: popular_api_client.id,
        api_credential_id: popular_payload.fetch(:credential).id,
        access_recording_id: access_recording.id,
        root_recording_id: workspace_root_recording.id,
        remote_ip: "10.20.0.2"
      )
    end

    switch_to_root(workspace_root_recording)

    get "/api/sections/api"

    assert_response :success
    assert_includes response.body, "API keys"
    assert_includes response.body, "/api/screens/api_keys"
    assert_includes response.body, "/api/screens/api_requests"
    assert_includes response.body, "widgets.recording_studio_api.requests_last_four_weeks"
    assert_includes response.body, "widgets.recording_studio_api.most_used_keys"
    # Buttons may render as <a> or <button>; gather both
    section_links = Nokogiri::HTML(response.body).css("a, button").select do |el|
      ["Create API key", "API keys", "API requests"].include?(el.text.strip)
    end

    assert_equal(["Create API key", "API keys", "API requests"].sort, section_links.map { |el| el.text.strip }.sort)
    classes = section_links.map { |el| el["class"].to_s }
    assert classes.any? { |c| c.include?("--button-primary-background-color") }, "expected primary button class in one of: #{classes.inspect}"
    assert classes.any? { |c| c.include?("--button-default-background-color") }, "expected default button class in one of: #{classes.inspect}"

    get "/api/sections/api/widgets/widgets.recording_studio_api.requests_last_four_weeks", params: { anchor_url: "/" }

    assert_response :success
    assert_includes response.body, "API requests"
    assert_includes response.body, "Last 4 weeks"
    assert_includes response.body, "flat-pack--chart"
    assert_includes response.body, "column"
    assert_includes response.body, "/api/screens/api_requests"
    assert_includes response.body, "group_by=day"

    get "/api/sections/api/widgets/widgets.recording_studio_api.most_used_keys", params: { anchor_url: "/" }

    assert_response :success
    assert_includes response.body, "Most used keys"
    assert_includes response.body, "Last 4 weeks"
    assert_includes response.body, "Popular API key"
    assert_includes response.body, "3 requests"
    assert_includes response.body, "Workspace API key"
    assert_includes response.body, "1 request"
    assert_includes response.body, "/api/screens/api_keys"

    get "/api/screens/api_keys"

    assert_response :success
    assert_includes response.body, 'data-recording-studio-default-layout="true"'
    refute_includes response.body, 'data-controller="flat-pack--sidebar-layout"'
    assert_includes response.body, "API keys"
    assert_includes response.body, "API keys for API access workspace"
    assert_select %(select[name="status"] option[value="active"][selected]), text: "Active", count: 1
    assert_select %(nav.flat-pack-page-nav a[href="/api"]), count: 1
    refute_includes response.body, "return_to=%2Fadmin"

    get "/recording_studio_api/api_clients/#{api_client.id}/edit", params: { anchor_url: "/", close_url: "/api/screens/api_keys" }

    assert_response :success
    assert_includes response.body, 'data-recording-studio-default-layout="true"'
    refute_includes response.body, 'data-controller="flat-pack--sidebar-layout"'
    assert_includes response.body, "Edit API key"
    assert_select %(nav.flat-pack-page-nav a[href="/"][aria-label="Close"]), count: 1

    get "/api/screens/api_keys/table"

    assert_response :success
    assert_includes response.body, "Workspace API key"
    api_client_href = "/recording_studio_api/api_clients/#{api_client.id}?close_url=%2Fapi%2Fscreens%2Fapi_keys"
    assert_select %(a[href="#{api_client_href}"][data-turbo-frame="_top"]), text: "Workspace API key", count: 1
    assert_includes response.body, rotated_credential.oauth_client_id
    assert_includes response.body, "Active"
    # No inline debug snippets
    # Action links moved to the detail view; table no longer includes rotate/revoke action labels

    get "/api/screens/api_keys/table", params: { status: "revoked", columns: %w[name api_key access_point role status] }

    assert_response :success
    assert_includes response.body, payload.fetch(:credential).oauth_client_id
    assert_includes response.body, "Revoked"
    refute_includes response.body, rotated_credential.oauth_client_id

    get "/api/screens/api_requests/table", params: { api_credential_id: rotated_credential.id }

    assert_response :success
    table_headers = css_select("thead th").map { |header| header.text.squish }
    assert_includes table_headers.first, "Occurred"
    assert_includes table_headers.second, "Name"
    assert_includes response.body, "Workspace API key"
    assert_includes response.body, "/recording_studio_api/api/v1/workspaces"
    assert_includes response.body, "api_credential_id=#{rotated_credential.id}"
  end

  test "renders site admin API section from the admin root" do
    switch_to_root(@admin_root_recording)

    2.times do |index|
      RecordingStudioApi::ApiRequestLog.create!(
        occurred_at: index.days.ago,
        request_id: "rs-admin-site-wide-#{index}",
        request_method: "GET",
        request_path: "/recording_studio_api/api/v1/site-wide-pages",
        status_code: 200,
        duration_ms: 40 + index,
        rate_limited: false,
        remote_ip: "10.40.0.#{index + 1}"
      )
    end

    2.times do |index|
      RecordingStudioApi::ApiRequestLog.create!(
        occurred_at: index.days.ago,
        request_id: "rs-admin-site-wide-server-error-#{index}",
        request_method: "GET",
        request_path: "/recording_studio_api/api/v1/site-wide-errors",
        status_code: 500 + index,
        duration_ms: 90 + index,
        rate_limited: false,
        remote_ip: "10.41.0.#{index + 1}"
      )
    end

    2.times do |index|
      RecordingStudioApi::ApiRequestLog.create!(
        occurred_at: index.days.ago,
        request_id: "rs-admin-site-wide-client-error-#{index}",
        request_method: "GET",
        request_path: "/recording_studio_api/api/v1/site-wide-client-errors",
        status_code: 400 + index,
        duration_ms: 70 + index,
        rate_limited: false,
        remote_ip: "10.42.0.#{index + 1}"
      )
    end

    RecordingStudioApi::ApiRequestLog.create!(
      occurred_at: Time.current,
      request_id: "rs-admin-site-wide-client-error-child",
      request_method: "GET",
      request_path: "/recording_studio_api/api/v1/site-wide-client-errors/child",
      status_code: 400,
      duration_ms: 75,
      rate_limited: false,
      remote_ip: "10.42.0.3"
    )

    RecordingStudioApi::ApiRequestLog.create!(
      occurred_at: 5.weeks.ago,
      request_id: "rs-admin-site-wide-old",
      request_method: "GET",
      request_path: "/recording_studio_api/api/v1/old-pages",
      status_code: 200,
      duration_ms: 80,
      rate_limited: false,
      remote_ip: "10.40.0.9"
    )

    RecordingStudioApi::ApiRequestLog.create!(
      occurred_at: 3.days.ago,
      request_id: "rs-admin-site-wide-unauthenticated",
      request_method: "GET",
      request_path: "/recording_studio_api/api/v1/authentication-failure",
      status_code: 401,
      duration_ms: 72,
      rate_limited: false,
      remote_ip: "10.42.0.21"
    )

    RecordingStudioApi::ApiRequestLog.create!(
      occurred_at: 2.days.ago,
      request_id: "rs-admin-site-wide-forbidden",
      request_method: "GET",
      request_path: "/recording_studio_api/api/v1/authorization-failure",
      status_code: 403,
      duration_ms: 73,
      rate_limited: false,
      remote_ip: "10.42.0.22"
    )

    get "/admin/api", params: { anchor_url: "/" }

    assert_response :success
    assert_includes response.body, "Admin API"
    assert_includes response.body, "Monitor and administer API access across the site."
    assert_includes response.body, "/admin/api/screens/admin_api_requests?anchor_url=%2F"
    assert_includes response.body, "/admin/api/screens/admin_api_failing_endpoints?anchor_url=%2F"
    assert_includes response.body, "/recording_studio_api/admin_api/settings?anchor_url=%2F"
    assert_includes response.body, "widgets.recording_studio_api.admin.requests_last_four_weeks"
    assert_includes response.body, "widgets.recording_studio_api.admin.api_latency_last_four_weeks"
    assert_includes response.body, "widgets.recording_studio_api.admin.client_errors_last_four_weeks"
    assert_includes response.body, "widgets.recording_studio_api.admin.server_errors_last_four_weeks"
    assert_includes response.body, "widgets.recording_studio_api.admin.authorization_failures_last_four_weeks"
    assert_includes response.body, "widgets.recording_studio_api.admin.top_failing_endpoints_last_four_weeks"
    assert_includes response.body, "widgets.recording_studio_api.admin.rate_limited_requests_last_four_weeks"
    assert_not_includes response.body, "Manage API access"

    api_requests_link = Nokogiri::HTML(response.body).css("a, button").find { |el| el.text.strip == "API requests" }
    assert_not_nil api_requests_link
    assert_includes api_requests_link["class"].to_s, "--button-default-background-color"
    assert_not_includes api_requests_link["class"].to_s, "--button-primary-background-color"

    get "/admin/api/sections/admin_api/widgets/widgets.recording_studio_api.admin.requests_last_four_weeks", params: { anchor_url: "/" }

    assert_response :success
    assert_includes response.body, "API requests"
    assert_includes response.body, "Site-wide API request volume for the last 4 weeks."
    assert_includes response.body, "Last 4 weeks"
    assert_includes response.body, "flat-pack--chart"
    assert_includes response.body, "area"
    assert_includes response.body, "/admin/api/screens/admin_api_requests"
    assert_includes response.body, "anchor_url=%2F"
    assert_includes response.body, "group_by=day"
    assert_includes response.body, "7"

    get "/admin/api/sections/admin_api/widgets/widgets.recording_studio_api.admin.api_latency_last_four_weeks"

    assert_response :success
    assert_includes response.body, "API latency"
    assert_includes response.body, "Site-wide p95 API response time for the last 4 weeks."
    assert_includes response.body, "Last 4 weeks"
    assert_includes response.body, "flat-pack--chart"
    assert_includes response.body, "area"
    assert_includes response.body, "/admin/api/screens/admin_api_performance"
    assert_includes response.body, "group_by=day"
    assert_includes response.body, "ms"
    assert_match(/[+-]?\d+(?:\.\d+)?%/, response.body)

    get "/admin/api/sections/admin_api/widgets/widgets.recording_studio_api.admin.client_errors_last_four_weeks"

    assert_response :success
    assert_includes response.body, "Client errors"
    assert_includes response.body, "Site-wide client error volume for the last 4 weeks."
    assert_includes response.body, "Last 4 weeks"
    assert_includes response.body, "flat-pack--chart"
    assert_includes response.body, "area"
    assert_includes response.body, "/admin/api/screens/admin_api_requests"
    assert_includes response.body, "group_by=day"
    assert_includes response.body, "status=client_error"
    assert_includes response.body, "2"
    assert_match(/[+-]?\d+(?:\.\d+)?%/, response.body)

    get "/admin/api/sections/admin_api/widgets/widgets.recording_studio_api.admin.server_errors_last_four_weeks"

    assert_response :success
    assert_includes response.body, "Server errors"
    assert_includes response.body, "Site-wide server error volume for the last 4 weeks."
    assert_includes response.body, "Last 4 weeks"
    assert_includes response.body, "flat-pack--chart"
    assert_includes response.body, "area"
    assert_includes response.body, "/admin/api/screens/admin_api_requests"
    assert_includes response.body, "group_by=day"
    assert_includes response.body, "status=server_error"
    assert_includes response.body, "2"
    assert_match(/[+-]?\d+(?:\.\d+)?%/, response.body)

    get "/admin/api/sections/admin_api/widgets/widgets.recording_studio_api.admin.authorization_failures_last_four_weeks"

    assert_response :success
    assert_includes response.body, "Authorization failures"
    assert_includes response.body, "Site-wide unauthenticated and forbidden API requests for the last 4 weeks."
    assert_includes response.body, "Unauthenticated (401)"
    assert_includes response.body, "Forbidden (403)"
    assert_includes response.body, "status=authorization_failure"
    assert_includes response.body, "2"

    get "/admin/api/sections/admin_api/widgets/widgets.recording_studio_api.admin.top_failing_endpoints_last_four_weeks"

    assert_response :success
    assert_includes response.body, "Top failing endpoints"
    assert_includes response.body, "API endpoints with the most client and server errors over the last 4 weeks."
    assert_includes response.body, "/site-wide-errors"
    assert_includes response.body, "/site-wide-client-errors"
    assert_select "span[class*='badge-info-background-color']", text: "GET", minimum: 1
    assert_select "li[role=listitem]", text: %r{GET /site-wide-errors\s*2}, minimum: 1
    assert_not_includes response.body, "(501)"
    assert_not_includes response.body, "(401)"
    assert_includes response.body, "/admin/api/screens/admin_api_failing_endpoints"
    assert_not_includes response.body, "GET /recording_studio_api/api/v1/pages"

    get "/admin/api/screens/admin_api_failing_endpoints"

    assert_response :success
    assert_includes response.body, "Failing endpoints"
    assert_includes response.body, "Site-wide endpoint failures relative to total API request volume."
    assert_select %(input[type="hidden"][name="date_range_preset"][value="last_4_weeks"]), count: 1
    assert_select "turbo-frame#screen-chart span", text: "0%", count: 0

    get "/admin/api/screens/admin_api_failing_endpoints/chart", params: {
      start_date: 27.days.ago.to_date.iso8601,
      end_date: Date.current.iso8601
    }

    assert_response :success
    assert_includes response.body, "Failure rate by endpoint"
    assert_includes response.body, 'data-flat-pack--chart-type-value="bar"'
    chart_body = CGI.unescapeHTML(response.body)
    assert_includes chart_body, '"name":"Failure rate (%)"'
    assert_includes chart_body, '"GET /site-wide-client-errors"'
    assert_includes chart_body, '"GET /site-wide-errors"'
    assert_match(/"data":\[100\.0/, chart_body)

    get "/admin/api/screens/admin_api_failing_endpoints/table", params: {
      start_date: 27.days.ago.to_date.iso8601,
      end_date: Date.current.iso8601
    }

    assert_response :success
    assert_includes response.body, "/site-wide-errors"
    assert_includes response.body, "/site-wide-client-errors"
    assert_includes response.body, "100.0%"
    assert_includes response.body, "2"
    assert_not_includes response.body, "/site-wide-pages"

    get "/admin/api/sections/admin_api/widgets/widgets.recording_studio_api.admin.rate_limited_requests_last_four_weeks"

    assert_response :success
    assert_includes response.body, "Rate limited requests"
    assert_includes response.body, "Site-wide rate-limited API requests for the last 4 weeks."
    assert_includes response.body, "Last 4 weeks"
    assert_includes response.body, "flat-pack--chart"
    assert_includes response.body, "area"
    assert_includes response.body, "/admin/api/screens/admin_api_requests"
    assert_includes response.body, "group_by=day"
    assert_includes response.body, "rate_limited=true"
    assert_includes response.body, "1"

    get "/admin/api/screens/admin_api_requests", params: {
      start_date: 27.days.ago.to_date.iso8601,
      end_date: Date.current.iso8601,
      group_by: "day"
    }

    assert_response :success
    assert_includes response.body, "API requests"
    assert_includes response.body, "Site-wide API request activity across every API client."
    assert_includes response.body, "area"
    assert_select 'button[data-modal-id="screen-filters-modal"]', count: 1

    get "/admin/api/screens/admin_api_requests/table", params: {
      start_date: 27.days.ago.to_date.iso8601,
      end_date: Date.current.iso8601,
      group_by: "day"
    }

    assert_response :success
    assert_includes response.body, "/recording_studio_api/api/v1/site-wide-pages"
    assert_includes response.body, "/recording_studio_api/api/v1/pages"
    assert_select '[role="tooltip"]', text: "/recording_studio_api/api/v1/site-wide-pages", minimum: 1
    assert_not_includes response.body, "/recording_studio_api/api/v1/old-pages"

    get "/admin/api/screens/admin_api_requests/table", params: {
      start_date: 27.days.ago.to_date.iso8601,
      end_date: Date.current.iso8601,
      group_by: "day",
      status: "server_error"
    }

    assert_response :success
    assert_includes response.body, "/recording_studio_api/api/v1/site-wide-errors"
    assert_not_includes response.body, "/recording_studio_api/api/v1/site-wide-pages"

    get "/admin/api/screens/admin_api_requests/table", params: {
      start_date: 27.days.ago.to_date.iso8601,
      end_date: Date.current.iso8601,
      group_by: "day",
      status: "client_error"
    }

    assert_response :success
    assert_includes response.body, "/recording_studio_api/api/v1/site-wide-client-errors"
    assert_not_includes response.body, "/recording_studio_api/api/v1/site-wide-pages"
    assert_not_includes response.body, "/recording_studio_api/api/v1/site-wide-errors"

    get "/admin/api/screens/admin_api_requests/table", params: {
      start_date: 27.days.ago.to_date.iso8601,
      end_date: Date.current.iso8601,
      group_by: "day",
      status: "failed",
      request_path: "/recording_studio_api/api/v1/site-wide-client-errors"
    }

    assert_response :success
    assert_includes response.body, "/recording_studio_api/api/v1/site-wide-client-errors"
    assert_not_includes response.body, "/recording_studio_api/api/v1/site-wide-client-errors/child"
    assert_not_includes response.body, "/recording_studio_api/api/v1/site-wide-errors"

    get "/admin/api/screens/admin_api_requests/table", params: {
      start_date: 27.days.ago.to_date.iso8601,
      end_date: Date.current.iso8601,
      group_by: "day",
      status: "authorization_failure"
    }

    assert_response :success
    assert_includes response.body, "/recording_studio_api/api/v1/authentication-failure"
    assert_includes response.body, "/recording_studio_api/api/v1/authorization-failure"
    assert_not_includes response.body, "/recording_studio_api/api/v1/site-wide-pages"
    assert_not_includes response.body, "/recording_studio_api/api/v1/site-wide-errors"

    get "/admin/api/screens/admin_api_requests/table", params: {
      start_date: 27.days.ago.to_date.iso8601,
      end_date: Date.current.iso8601,
      group_by: "day",
      rate_limited: "true"
    }

    assert_response :success
    assert_includes response.body, "/recording_studio_api/api/v1/pages"
    assert_not_includes response.body, "/recording_studio_api/api/v1/site-wide-pages"
  end

  test "site admins can filter credentials by root and revoke an active credential" do
    _first_root_recording, first_access_recording = create_access_recording_for(
      user: @user,
      workspace_name: "First credential root",
      role: :admin
    )
    _second_root_recording, second_access_recording = create_access_recording_for(
      user: @user,
      workspace_name: "Second credential root",
      role: :admin
    )
    first_payload = provision_api_client_for(access_recording: first_access_recording, name: "First site credential")
    second_payload = provision_api_client_for(access_recording: second_access_recording, name: "Second site credential")

    switch_to_root(@admin_root_recording)

    get "/admin/api"

    assert_response :success
    assert_includes response.body, "/admin/api/screens/admin_api_credentials"
    assert_includes response.body, "API credentials"

    get "/admin/api/screens/admin_api_credentials"

    assert_response :success
    assert_select %(select[name="status"] option[value="active"][selected]), text: "Active", count: 1
    assert_select %(select[name="status"] option[value=""]:not([disabled])), count: 1
    assert_select %(select[name="root_recording_id"] option[value=""]:not([disabled])), count: 1
    assert_select %(select[name="root_type"] option[value=""]:not([disabled])), count: 1
    assert_select %(select[name="root_recording_id"] option[value="First credential root"]), text: "First credential root", count: 1

    get "/admin/api/screens/admin_api_credentials/table"

    assert_response :success
    assert_includes response.body, "First credential root"
    assert_includes response.body, "Second credential root"
    assert_includes response.body, "First site credential"
    assert_includes response.body, "Second site credential"
    assert_includes response.body, first_payload.fetch(:credential).oauth_client_id
    assert_includes response.body, second_payload.fetch(:credential).oauth_client_id
    revoke_path = "/recording_studio_api/admin_api/credentials/#{first_payload.fetch(:credential).id}/revoke?close_url=%2Fadmin%2Fapi%2Fscreens%2Fadmin_api_credentials"
    assert_select %(a[href="#{revoke_path}"][data-turbo-method="post"][data-turbo-confirm="Revoke this API credential? This cannot be undone."]), text: "Revoke", count: 1

    get "/admin/api/screens/admin_api_credentials/table", params: {
      root_recording_id: "First credential root"
    }

    assert_response :success
    assert_includes response.body, "First site credential"
    refute_includes response.body, "Second site credential"

    get "/admin/api/screens/admin_api_credentials/table", params: {
      status: "",
      root_recording_id: "",
      root_type: ""
    }

    assert_response :success
    assert_includes response.body, "First site credential"
    assert_includes response.body, "Second site credential"

    post "/recording_studio_api/admin_api/credentials/#{first_payload.fetch(:credential).id}/revoke", params: {
      close_url: "/admin/api/screens/admin_api_credentials"
    }

    assert_redirected_to "/admin/api/screens/admin_api_credentials"
    assert_not_nil first_payload.fetch(:credential).reload.revoked_at
    assert_nil second_payload.fetch(:credential).reload.revoked_at

    get "/admin/api/screens/admin_api_credentials/table"

    assert_response :success
    assert_not_includes response.body, "First site credential"
    assert_includes response.body, "Second site credential"

    revoked_at = first_payload.fetch(:credential).revoked_at.utc.strftime("%Y-%m-%d %H:%M UTC")
    get "/admin/api/screens/admin_api_credentials/table", params: { status: "revoked" }

    assert_response :success
    assert_includes response.body, "First site credential"
    assert_select '[role="tooltip"]', text: "Revoked at #{revoked_at}", count: 1
  end

  test "admin workspace provisions and monitors operations API credentials separately" do
    switch_to_root(@admin_root_recording)

    get "/admin/api/operations"

    assert_response :success
    assert_includes response.body, "Admin Operations API"
    assert_includes response.body, "api_key=operations"

    post "/recording_studio_api/api_clients", params: {
      api_client: {
        api_key: "operations",
        root_type: "AdminRoot",
        root_recording_id: @admin_root_recording.id,
        access_point_recording_id: @admin_root_recording.id,
        role: "admin",
        api_client_name: "Operations monitoring client",
        expires_at: ""
      }
    }

    assert_response :created
    assert_equal "operations", RecordingStudioApi::ApiClient.find_by!(name: "Operations monitoring client").api_key

    get "/admin/api/operations/screens/admin_api_credentials/table", params: { api_key: "operations" }

    assert_response :success
    assert_includes response.body, "Operations monitoring client"

    get "/admin/api/screens/admin_api_credentials/table"

    assert_response :success
    assert_not_includes response.body, "Operations monitoring client"
  end

  test "API admin viewers cannot revoke credentials" do
    _workspace_root_recording, access_recording = create_access_recording_for(
      user: @user,
      workspace_name: "Protected site credential root",
      role: :admin
    )
    credential = provision_api_client_for(
      access_recording: access_recording,
      name: "Protected site credential"
    ).fetch(:credential)

    switch_to_root(@admin_root_recording)
    get "/admin/api"

    admin_api = RecordingStudioApi::AdminApi.find_by!(key: "api")
    admin_api_recording = RecordingStudio::Recording.unscoped.find_by!(
      recordable: admin_api,
      root_recording_id: @admin_root_recording.id,
      parent_recording_id: @admin_root_recording.id
    )
    viewer = create_user(email: "api-admin-viewer-#{SecureRandom.hex(4)}@example.com")
    create_access_recording(parent_recording: @admin_root_recording, user: viewer, role: :view)
    reset!
    sign_in viewer, scope: :user
    switch_to_root(@admin_root_recording)

    assert_equal :view, RecordingStudioAccessible.role_for(actor: viewer, recording: admin_api_recording)
    assert_equal :admin, RecordingStudioApi.configuration.access_management_edit_role
    refute RecordingStudioApi::AccessManagementPolicy.new(actor: viewer).can_manage_recording?(admin_api_recording)

    get "/admin/api/screens/admin_api_credentials/table"

    assert_response :success
    assert_equal viewer, request.env.fetch("warden").user(:user)
    assert_includes response.body, "Protected site credential"
    refute_includes response.body, "Revoke"

    post "/recording_studio_api/admin_api/credentials/#{credential.id}/revoke", params: {
      close_url: "/admin/api/screens/admin_api_credentials"
    }

    assert_response :forbidden
    assert_nil credential.reload.revoked_at
  end

  test "API access requests screen shows chart and widgets for request analytics" do
    workspace_root_recording, access_recording = create_access_recording_for(
      user: @user,
      workspace_name: "Analytics workspace",
      role: :admin
    )
    payload = provision_api_client_for(access_recording: access_recording, name: "Analytics API key")
    api_client = payload.fetch(:api_client)
    other_payload = provision_api_client_for(access_recording: access_recording, name: "Other API key")
    other_api_client = other_payload.fetch(:api_client)

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

    RecordingStudioApi::ApiRequestLog.create!(
      occurred_at: Time.current,
      request_id: "rs-analytics-other",
      request_method: "GET",
      request_path: "/recording_studio_api/api/v1/other-pages",
      status_code: 200,
      duration_ms: 75,
      rate_limited: false,
      api_client_id: other_api_client.id,
      api_credential_id: other_payload.fetch(:credential).id,
      access_recording_id: access_recording.id,
      root_recording_id: workspace_root_recording.id,
      remote_ip: "10.30.0.3"
    )

    switch_to_root(workspace_root_recording)

    get "/api/screens/api_requests", params: { api_client_id: api_client.id }

    assert_response :success
    assert_select 'button[data-modal-id="screen-filters-modal"]', count: 1
    assert_select "form#screen-inline-filters-form" do
      assert_select %(input[name="date_range_preset"]), count: 1
      assert_select %(select[name="group_by"]), count: 1
    end
    assert_select "form#screen-filters-mobile-form" do
      assert_select %(select[name="api_client_name"]), count: 1
      assert_select %(select[name="api_client_name"] option[value=""]:not([disabled])), count: 1
      assert_select %(select[name="api_client_name"] option[value="Analytics API key"]), count: 1
      assert_select %(select[name="status"] option[value=""][disabled][selected]), count: 1
    end
    assert_includes response.body, "All API keys"
    assert_includes response.body, "Analytics API key"
    assert_includes response.body, "Status"
    refute_includes response.body, "Avg duration"
    refute_includes response.body, "Error rate"

    get "/api/screens/api_requests/table", params: { api_client_name: "Analytics API key" }

    assert_response :success
    assert_includes response.body, "/recording_studio_api/api/v1/pages"
    refute_includes response.body, "/recording_studio_api/api/v1/other-pages"

    get "/api/screens/api_requests/table", params: { api_client_name: "" }

    assert_response :success
    assert_includes response.body, "/recording_studio_api/api/v1/pages"
    assert_includes response.body, "/recording_studio_api/api/v1/other-pages"

    get "/api/screens/api_requests/chart", params: {
      api_client_id: api_client.id,
      api_client_name: "Analytics API key",
      start_date: 10.days.ago.to_date.iso8601,
      end_date: Date.current.iso8601,
      group_by: "year"
    }

    assert_response :success
    chart_body = CGI.unescapeHTML(response.body)
    assert_includes chart_body, 'data-flat-pack--chart-type-value="bar"'
    assert_includes chart_body, '"name":"Analytics API key"'
    refute_includes chart_body, '"name":"Other API key"'
    assert_includes chart_body, "\"x\":\"#{Time.current.year}\",\"y\":6"
    assert_includes chart_body, '"stacked":true'
    assert_includes chart_body, '"horizontal":false'
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

  test "dummy home links to RecordingStudioAdmin API section" do
    workspace_root_recording, access_recording = create_access_recording_for(
      user: @user,
      workspace_name: "Redirect workspace",
      role: :admin
    )
    provision_api_client_for(access_recording: access_recording, name: "Redirect API key")
    switch_to_root(workspace_root_recording)

    get "/"

    assert_response :success
    assert_includes response.body, "/api?anchor_url=%2F"
    refute_includes response.body, "root_recording_id=#{workspace_root_recording.id}"
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