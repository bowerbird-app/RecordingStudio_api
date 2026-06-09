# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "../test_helper"
require_relative "../dummy/config/environment"

require "devise/test/integration_helpers"
require "rails/test_help"
require "securerandom"
require_relative "../support/api_dummy_helpers"

class AccessRequestsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ApiDummyHelpers

  TEST_PASSWORD = "AccessRequestPassword!2026"

  setup do
    @user = User.find_or_create_by!(email: "access-requests@example.com") do |user|
      user.password = TEST_PASSWORD
      user.password_confirmation = TEST_PASSWORD
    end

    sign_in @user

    @workspace_root_recording, @workspace_access_recording = create_access_recording_for(
      user: @user,
      workspace_name: "UI Workspace",
      role: :admin
    )
  end

  test "renders the workspace access request form" do
    get "/recording_studio_api/api_clients/new", params: { root_type: "Workspace" }

    assert_response :success
    assert_select %(nav.flat-pack-page-nav a[href="/"][aria-label="Close"]), count: 1
    assert_select "button", text: "Cancel", count: 0
    assert_includes response.body, "Add API access"
    assert_includes response.body, "Create access"
    assert_includes response.body, "Access point"
    assert_includes response.body, "Name"
    assert_includes response.body, "Role"
    assert_includes response.body, "Expires"
    assert_select %(input[name="api_client[expires_at]"][placeholder="Never"]), count: 1
    assert_not_includes response.body, "Access role"
    assert_not_includes response.body, "Credential expiry"
    assert_not_includes response.body, "Top-level recording"
    assert_not_includes response.body, "access_request_root_recording_id"
    assert_not_includes response.body, "Workspace root"
    assert_not_includes response.body, "Boundary minimum role"
  end

  test "submitting the form creates the access hierarchy and shows the client secret" do
    post "/recording_studio_api/api_clients", params: {
      api_client: {
        root_type: "Workspace",
        access_point_recording_id: @workspace_root_recording.id,
        role: "admin",
        api_client_name: "UI provisioned client",
        expires_at: ""
      }
    }

    assert_response :created
    assert_select %(nav.flat-pack-page-nav a[href="/"][aria-label="Close"]), count: 1
    assert_includes response.body, "Workspace API access created"
    assert_includes response.body, "UI provisioned client"
    assert_includes response.body, "Client secret"

    api_client = RecordingStudioApi::ApiClient.order(:created_at, :id).last
    access_recording = api_client.access_recording
    eligible_workspace_root_ids = RecordingStudio::Recording.where(parent_recording_id: nil, recordable_type: "Workspace").pluck(:id)

    assert_not_nil access_recording
    assert_includes eligible_workspace_root_ids, access_recording.root_recording_id
    assert_equal "RecordingStudio::Access", access_recording.recordable_type
    assert_equal api_client, access_recording.recordable.actor
    refute_equal @workspace_access_recording.id, access_recording.id
    assert_not_includes response.body, access_recording.id.to_s
  end

  test "index lists API access including descendant child access" do
    direct_api_client = create_api_client_for(
      parent_recording: @workspace_root_recording,
      name: "Direct API client"
    )
    direct_oauth_client_id = direct_api_client.credentials.max_by(&:created_at).oauth_client_id
    direct_expires_at = direct_api_client.credentials.max_by(&:created_at).expires_at.in_time_zone
    direct_exact_expiry = "#{direct_expires_at.strftime("%B %-d, %Y at %-l:%M %p")} #{direct_expires_at.strftime("%Z")}".strip

    child_folder_recording = RecordingStudio::Recording.create!(
      recordable: Folder.create!(name: "Nested Folder"),
      parent_recording: @workspace_root_recording
    )

    nested_api_client = create_api_client_for(
      parent_recording: child_folder_recording,
      name: "Nested API client"
    )

    get "/recording_studio_api/api_clients", params: { root_recording_id: @workspace_root_recording.id, close_url: "/workspace" }

    assert_response :success
    assert_select %(nav.flat-pack-page-nav a[href="/workspace"][aria-label="Close"]), count: 1
    assert_includes response.body, "API keys"
    assert_includes response.body, "Total API keys"
    assert_match(/Total API keys.{0,300}>\s*2\s*</m, response.body)
    assert_includes response.body, "API access below Workspace: UI Workspace."
    assert_includes response.body, "Name"
    assert_includes response.body, "API key"
    assert_includes response.body, "Access point"
    assert_includes response.body, "Expires"
    assert_not_includes response.body, "Root"
    assert_not_includes response.body, "Access recording"
    assert_not_includes response.body, "Details"
    assert_includes response.body, direct_api_client.name
    assert_includes response.body, direct_oauth_client_id
    assert_includes response.body, "Workspace"
    assert_includes response.body, nested_api_client.name
    assert_includes response.body, "Nested Folder"
    assert_select %(a[href="/recording_studio_api/api_clients/requests_chart?close_url=%2Fworkspace&root_recording_id=#{@workspace_root_recording.id}"]), text: "Full screen", count: 1
    assert_select %(a[href="/recording_studio_api/api_clients/#{direct_api_client.id}?close_url=%2Fworkspace"]), text: direct_api_client.name
    assert_select %(a[href="/recording_studio_api/api_clients/#{nested_api_client.id}?close_url=%2Fworkspace"]), text: nested_api_client.name
    assert_match(/in \d+\s+(minute|minutes|hour|hours|day|days|week|weeks|month|months|year|years)/, response.body)
    assert_includes response.body, direct_exact_expiry
    expected_day_labels = (6.days.ago.to_date..Date.current).map { |day| day.strftime("%a") }
    expected_day_labels.each do |day_label|
      assert_includes response.body, day_label
    end
    assert_select "span.underline.decoration-dotted.underline-offset-2", minimum: 1
  end

  test "requests chart page renders full-screen chart and links back to api clients" do
    get "/recording_studio_api/api_clients/requests_chart", params: {
      root_recording_id: @workspace_root_recording.id,
      close_url: "/workspace"
    }

    assert_response :success
    assert_includes response.body, "API requests"
    assert_includes response.body, "Last 7 days"
    assert_match(/\[\s*0\s*,\s*0\s*,\s*0\s*,\s*0\s*,\s*0\s*,\s*0\s*,\s*0\s*\]/, response.body)
    assert_select "turbo-frame#requests-chart-frame", count: 1
    assert_includes response.body, "flat-pack--auto-submit"
    assert_includes response.body, "Date Range"
    assert_includes response.body, "All statuses"
    assert_select %(nav.flat-pack-page-nav a[href="/workspace"][aria-label="Close"]), count: 1
  end

  test "requests chart filters series by date range and status" do
    api_client = create_api_client_for(parent_recording: @workspace_root_recording, name: "Filtered chart client")

    ensure_api_request_logs_table!

    RecordingStudioApi::ApiRequestLog.where(api_client_id: api_client.id).delete_all

    request_dates = [2.days.ago.to_date, 1.day.ago.to_date, Date.current]
    request_dates.each_with_index do |request_date, index|
      RecordingStudioApi::ApiRequestLog.create!(
        occurred_at: request_date.in_time_zone.change(hour: 10),
        request_id: "chart-filter-success-#{index}",
        request_method: "GET",
        request_path: "/api/v1/recordings",
        status_code: 200,
        duration_ms: 40,
        api_client_id: api_client.id,
        api_credential_id: api_client.credentials.max_by(&:created_at).id,
        access_recording_id: api_client.access_recording_id,
        root_recording_id: @workspace_root_recording.id
      )
    end

    RecordingStudioApi::ApiRequestLog.create!(
      occurred_at: 1.day.ago.in_time_zone.change(hour: 16),
      request_id: "chart-filter-client-error",
      request_method: "GET",
      request_path: "/api/v1/recordings",
      status_code: 404,
      duration_ms: 45,
      api_client_id: api_client.id,
      api_credential_id: api_client.credentials.max_by(&:created_at).id,
      access_recording_id: api_client.access_recording_id,
      root_recording_id: @workspace_root_recording.id
    )

    get "/recording_studio_api/api_clients/requests_chart", params: {
      root_recording_id: @workspace_root_recording.id,
      start_date: 2.days.ago.to_date.iso8601,
      end_date: Date.current.iso8601,
      status: "success"
    }

    assert_response :success
    assert_match(/\[\s*1\s*,\s*1\s*,\s*1\s*\]/, response.body)
    refute_match(/\[\s*1\s*,\s*2\s*,\s*1\s*\]/, response.body)
    assert_includes response.body, "value=\"success\""
  end

  test "index infinite scroll returns paged table content for xhr page requests" do
    52.times do |index|
      create_api_client_for(
        parent_recording: @workspace_root_recording,
        name: format("Infinite API client %02d", index + 1)
      )
    end

    get "/recording_studio_api/api_clients", params: { root_recording_id: @workspace_root_recording.id }

    assert_response :success
    assert_includes response.body, "Infinite API client 01"
    assert_not_includes response.body, "Infinite API client 26"
    assert_includes response.body, "flat-pack--pagination-infinite"
    assert_includes response.body, "page=2"

    get "/recording_studio_api/api_clients", params: { root_recording_id: @workspace_root_recording.id, page: 2 }, headers: { "X-Requested-With" => "XMLHttpRequest" }

    assert_response :success
    assert_not_includes response.body, "API keys"
    assert_not_includes response.body, "Infinite API client 01"
    assert_includes response.body, "Infinite API client 26"
    assert_includes response.body, "Infinite API client 50"
    assert_includes response.body, "page=3"
  end

  test "page nav falls back to the default close url when close url is unsafe" do
    get "/recording_studio_api/api_clients/new", params: { root_type: "Workspace", close_url: "https://example.com/escape" }

    assert_response :success
    assert_select "nav.flat-pack-page-nav", count: 1
    assert_not_includes response.body, "https://example.com/escape"
  end

  test "view-only access can see api access but cannot change it" do
    view_user = create_user(email: "view-access@example.com")
    sign_in view_user

    view_root_recording, = create_access_recording_for(user: view_user, role: :view)
    @user = view_user
    view_api_client = create_api_client_for(
      parent_recording: view_root_recording,
      name: "View-only API client",
      role: :view
    )

    get "/recording_studio_api/api_clients", params: { root_recording_id: view_root_recording.id }

    assert_response :success
    assert_includes response.body, view_api_client.name

    get "/recording_studio_api/api_clients/new", params: { root_type: "Workspace" }
    assert_response :forbidden

    patch "/recording_studio_api/api_clients/#{view_api_client.id}", params: {
      api_client: {
        api_client_name: "Blocked rename",
        expires_at: ""
      }
    }

    assert_response :forbidden

    view_token = RecordingStudioApi::ApiAccessToken.create!(
      credential: view_api_client.credentials.max_by(&:created_at),
      token_digest: "view_only_token_digest_#{SecureRandom.hex(16)}",
      token_prefix: "tok-view",
      expires_at: 2.days.from_now
    )

    post "/recording_studio_api/api_clients/#{view_api_client.id}/tokens/#{view_token.id}/revoke"

    assert_response :forbidden

    post "/recording_studio_api/api_clients/#{view_api_client.id}/revoke"

    assert_response :forbidden
  end

  test "index subtitle shows folder name when scoped to a folder root" do
    folder = Folder.create!(name: "Scoped Folder")
    folder_root_recording = RecordingStudio::Recording.create!(recordable: folder)
    api_client = create_api_client_for(parent_recording: folder_root_recording, name: "Folder scoped client")

    get "/recording_studio_api/api_clients", params: { root_recording_id: folder_root_recording.id }

    assert_response :success
    assert_includes response.body, "API access below Folder: Scoped Folder."
    assert_includes response.body, api_client.name
  end

  test "index subtitle shows workspace name when scoped to a workspace root" do
    create_api_client_for(parent_recording: @workspace_root_recording, name: "Workspace scoped client")

    get "/recording_studio_api/api_clients", params: { recording_id: @workspace_root_recording.id }

    assert_response :success
    assert_includes response.body, "API access below Workspace: UI Workspace."
  end

  test "index subtitle shows lower access-point recording name when scoped root has one nested branch" do
    nested_folder_recording = RecordingStudio::Recording.create!(
      recordable: Folder.create!(name: "Nested Access Point"),
      parent_recording: @workspace_root_recording
    )
    create_api_client_for(parent_recording: nested_folder_recording, name: "Nested only client")

    get "/recording_studio_api/api_clients", params: { root_recording_id: @workspace_root_recording.id }

    assert_response :success
    assert_includes response.body, "API access below Folder: Nested Access Point."
  end

  test "index filters API access to the anchored recording subtree" do
    direct_api_client = create_api_client_for(
      parent_recording: @workspace_root_recording,
      name: "Workspace root client"
    )

    nested_folder_recording = RecordingStudio::Recording.create!(
      recordable: Folder.create!(name: "Anchored Folder"),
      parent_recording: @workspace_root_recording
    )

    nested_api_client = create_api_client_for(
      parent_recording: nested_folder_recording,
      name: "Nested folder client"
    )

    get "/recording_studio_api/api_clients", params: { recording_id: nested_folder_recording.id }

    assert_response :success
    assert_includes response.body, "API access below Folder: Anchored Folder."
    assert_includes response.body, nested_api_client.name
    assert_not_includes response.body, direct_api_client.name
  end

  test "index shows empty state when no access has been given yet" do
    RecordingStudioApi::ApiAccessToken.delete_all
    RecordingStudioApi::ApiCredential.delete_all
    RecordingStudioApi::ApiClient.delete_all

    get "/recording_studio_api/api_clients"

    assert_response :success
    assert_includes response.body, "No API access given yet"
    assert_includes response.body, "Create API access from the demo home page to populate this list."
    assert_select %(a[href="/recording_studio_api/api_clients/new?close_url=%2F"]), text: "New", count: 1
  end

  test "index api keys list uses request log counts for visible clients" do
    direct_api_client = create_api_client_for(
      parent_recording: @workspace_root_recording,
      name: "Chart direct client"
    )

    nested_folder_recording = RecordingStudio::Recording.create!(
      recordable: Folder.create!(name: "Chart Folder"),
      parent_recording: @workspace_root_recording
    )

    nested_api_client = create_api_client_for(
      parent_recording: nested_folder_recording,
      name: "Chart nested client"
    )

    ensure_api_request_logs_table!

    RecordingStudioApi::ApiRequestLog.where(api_client_id: [direct_api_client.id, nested_api_client.id]).delete_all

    5.times do |index|
      RecordingStudioApi::ApiRequestLog.create!(
        occurred_at: Time.current - index.minutes,
        request_id: "chart-direct-#{index}",
        request_method: "GET",
        request_path: "/api/v1/recordings/direct",
        status_code: 200,
        duration_ms: 30,
        api_client_id: direct_api_client.id,
        api_credential_id: direct_api_client.credentials.max_by(&:created_at).id,
        access_recording_id: direct_api_client.access_recording_id,
        root_recording_id: @workspace_root_recording.id
      )
    end

    2.times do |index|
      RecordingStudioApi::ApiRequestLog.create!(
        occurred_at: Time.current - (index + 10).minutes,
        request_id: "chart-nested-#{index}",
        request_method: "POST",
        request_path: "/oauth/token",
        status_code: 200,
        duration_ms: 45,
        api_client_id: nested_api_client.id,
        api_credential_id: nested_api_client.credentials.max_by(&:created_at).id,
        access_recording_id: nested_api_client.access_recording_id,
        root_recording_id: @workspace_root_recording.id
      )
    end

    get "/recording_studio_api/api_clients", params: { root_recording_id: @workspace_root_recording.id }

    assert_response :success
    list_node = Nokogiri::HTML(response.body).at_css("#most-used-api-keys")
    refute_nil list_node

    list_text = list_node.text.gsub(/\s+/, " ").strip
    assert_includes list_text, "Chart direct client"
    assert_includes list_text, "5 requests"
    assert_includes list_text, "Chart nested client"
    assert_includes list_text, "2 requests"
    assert_operator list_text.index("Chart direct client"), :<, list_text.index("Chart nested client")
    assert_not_includes response.body, "Key A"
  end

  test "index subtitle falls back to root type label when multiple roots match" do
    another_workspace = Workspace.create!(name: "Another Workspace")
    another_root_recording = RecordingStudio::Recording.create!(recordable: another_workspace)
    create_api_client_for(parent_recording: @workspace_root_recording, name: "Workspace A client")
    create_api_client_for(parent_recording: another_root_recording, name: "Workspace B client")

    get "/recording_studio_api/api_clients", params: { root_type: "Workspace" }

    assert_response :success
    assert_includes response.body, "API access below Workspace."
  end

  test "create returns validation error for invalid expiry" do
    post "/recording_studio_api/api_clients", params: {
      api_client: {
        root_type: "Workspace",
        role: "admin",
        api_client_name: "Invalid expiry client",
        expires_at: "not-a-datetime"
      }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "Expiry must be a valid date and time"
  end

  test "show renders API access details" do
    api_client = create_api_client_for(parent_recording: @workspace_root_recording, name: "Details API client")
    oauth_client_id = api_client.credentials.max_by(&:created_at).oauth_client_id

    get "/recording_studio_api/api_clients/#{api_client.id}"

    assert_response :success
    assert_select %(nav.flat-pack-page-nav a[href="/"][aria-label="Close"]), count: 1
    assert_includes response.body, "Details API client"
    assert_includes response.body, "API key"
    assert_includes response.body, oauth_client_id
    assert_includes response.body, "API secret"
    assert_includes response.body, "Hidden after creation"
    assert_includes response.body, "Role"
    assert_includes response.body, "Expiry"
    assert_not_includes response.body, "Issued tokens"
    assert_not_includes response.body, "Active tokens"
    assert_not_includes response.body, "Revoked tokens"
    assert_not_includes response.body, "OAuth2 activity"
    assert_not_includes response.body, "Active grant sessions"
    assert_select %(div#machine-token-health[data-controller="flat-pack--section-title-anchor"]), count: 0
    assert_select %(a[href="#machine-token-health"][data-flat-pack--section-title-anchor-target="link"]), count: 0
    assert_select %(div#oauth2-activity[data-controller="flat-pack--section-title-anchor"]), count: 0
    assert_select %(a[href="#oauth2-activity"][data-flat-pack--section-title-anchor-target="link"]), count: 0
    assert_select %(a[href="/recording_studio_api/api_clients/#{api_client.id}/edit?close_url=%2F"]), text: "Edit"
    assert_select %(a[href="/recording_studio_api/api_clients/#{api_client.id}/tokens?close_url=%2F"]), text: "Tokens"
    assert_select %(a[href="/recording_studio_api/api_clients/#{api_client.id}/log?close_url=%2F"]), text: "Log"
    assert_select %(a[href="/recording_studio_api/api_clients/#{api_client.id}/revoke?close_url=%2F"][data-turbo-method="post"][data-turbo-confirm="Revoke this API key?"]), text: "Revoke"
    assert_not_includes response.body, "Back to API access list"
    assert_not_includes response.body, "Back to demo"
  end

  test "show revokes the latest credential" do
    api_client = create_api_client_for(parent_recording: @workspace_root_recording, name: "Revocable API client")
    latest_credential = api_client.credentials.max_by(&:created_at)

    post "/recording_studio_api/api_clients/#{api_client.id}/revoke"

    assert_redirected_to "/recording_studio_api/api_clients/#{api_client.id}?close_url=%2F"
    assert_not_nil latest_credential.reload.revoked_at

    get "/recording_studio_api/api_clients/#{api_client.id}"

    assert_response :success
    assert_select %(div[data-page-nav-right-slot="revoked-badge"]), count: 1
    assert_select %(div[data-page-nav-right-slot="revoked-badge"] span), text: "Revoked", count: 1
    assert_select %(a[href="/recording_studio_api/api_clients/#{api_client.id}/revoke?close_url=%2F"]), count: 0
  end

  test "index shows revoked and expired credentials in the expires column" do
    revoked_api_client = create_api_client_for(parent_recording: @workspace_root_recording, name: "Revoked API client")
    expired_api_client = create_api_client_for(parent_recording: @workspace_root_recording, name: "Expired API client")

    revoked_api_client.credentials.max_by(&:created_at).revoke!
    expired_api_client.credentials.max_by(&:created_at).update_columns(
      expires_at: 1.day.ago,
      updated_at: Time.current
    )

    get "/recording_studio_api/api_clients", params: { root_recording_id: @workspace_root_recording.id }

    assert_response :success
    assert_includes response.body, revoked_api_client.name
    assert_includes response.body, expired_api_client.name
    assert_includes response.body, "Revoked"
    assert_includes response.body, "Expired"
  end

  test "log lists API request rows for the selected api client only" do
    api_client = create_api_client_for(parent_recording: @workspace_root_recording, name: "Logged API client")
    other_api_client = create_api_client_for(parent_recording: @workspace_root_recording, name: "Other logged API client")

    ensure_api_request_logs_table!

    RecordingStudioApi::ApiRequestLog.create!(
      occurred_at: Time.current,
      request_id: "client-log-1",
      request_method: "GET",
      request_path: "/recording_studio_api/api/v1/workspaces",
      status_code: 200,
      duration_ms: 31,
      api_client_id: api_client.id,
      api_credential_id: api_client.credentials.max_by(&:created_at).id,
      access_recording_id: api_client.access_recording_id,
      root_recording_id: @workspace_root_recording.id
    )

    RecordingStudioApi::ApiRequestLog.create!(
      occurred_at: Time.current,
      request_id: "client-log-other",
      request_method: "POST",
      request_path: "/recording_studio_api/oauth/token",
      status_code: 201,
      duration_ms: 45,
      api_client_id: other_api_client.id,
      api_credential_id: other_api_client.credentials.max_by(&:created_at).id,
      access_recording_id: other_api_client.access_recording_id,
      root_recording_id: @workspace_root_recording.id
    )

    get "/recording_studio_api/api_clients/#{api_client.id}/log"

    assert_response :success
    assert_select %(nav.flat-pack-page-nav a[href="/"][aria-label="Close"]), count: 1
    assert_includes response.body, "/recording_studio_api/api_clients/#{api_client.id}"
    assert_includes response.body, "Logged API client"
    assert_includes response.body, "API call log"
    assert_includes response.body, "Occurred"
    assert_includes response.body, "Method"
    assert_includes response.body, "Path"
    assert_includes response.body, "Status"
    assert_includes response.body, "Duration"
    assert_includes response.body, "Request ID"
    assert_includes response.body, "client-log-1"
    assert_not_includes response.body, "client-log-other"
    assert_includes response.body, "/recording_studio_api/api/v1/workspaces"
    assert_not_includes response.body, "/recording_studio_api/oauth/token"
  end

  test "tokens lists child tokens for the selected api client only" do
    api_client = create_api_client_for(parent_recording: @workspace_root_recording, name: "Token parent client")
    other_api_client = create_api_client_for(parent_recording: @workspace_root_recording, name: "Other client")

    credential = api_client.credentials.max_by(&:created_at)
    other_credential = other_api_client.credentials.max_by(&:created_at)

    token = RecordingStudioApi::ApiAccessToken.create!(
      credential: credential,
      token_digest: "child_token_digest_#{SecureRandom.hex(16)}",
      token_prefix: "tok-main",
      expires_at: 2.days.from_now,
      last_used_at: 2.hours.ago
    )

    RecordingStudioApi::ApiAccessToken.create!(
      credential: other_credential,
      token_digest: "other_child_token_digest_#{SecureRandom.hex(16)}",
      token_prefix: "tok-other",
      expires_at: 3.days.from_now,
      last_used_at: 3.hours.ago
    )

    get "/recording_studio_api/api_clients/#{api_client.id}/tokens"

    assert_response :success
    assert_includes response.body, "Tokens"
    assert_includes response.body, "Token parent client"
    assert_includes response.body, "Prefix"
    assert_includes response.body, "Status"
    assert_includes response.body, "****main"
    assert_not_includes response.body, "tok-main"
    assert_not_includes response.body, "tok-other"
    assert_select %(form[action="/recording_studio_api/api_clients/#{api_client.id}/tokens/#{token.id}/revoke?close_url=%2F"] button), text: "Revoke", count: 1
    assert_select %(nav.flat-pack-page-nav a[href="/"][aria-label="Close"]), count: 1
  end

  test "tokens index shows revoke action and revoke marks token revoked" do
    api_client = create_api_client_for(parent_recording: @workspace_root_recording, name: "Revocable token client")
    credential = api_client.credentials.max_by(&:created_at)

    token = RecordingStudioApi::ApiAccessToken.create!(
      credential: credential,
      token_digest: "revocable_token_digest_#{SecureRandom.hex(16)}",
      token_prefix: "tok-revoke",
      expires_at: 2.days.from_now
    )

    get "/recording_studio_api/api_clients/#{api_client.id}/tokens"

    assert_response :success
    assert_select %(form[action="/recording_studio_api/api_clients/#{api_client.id}/tokens/#{token.id}/revoke?close_url=%2F"] button), text: "Revoke", count: 1

    post "/recording_studio_api/api_clients/#{api_client.id}/tokens/#{token.id}/revoke"

    assert_redirected_to "/recording_studio_api/api_clients/#{api_client.id}/tokens?close_url=%2F"
    assert_not_nil token.reload.revoked_at

    get "/recording_studio_api/api_clients/#{api_client.id}/tokens"

    assert_response :success
    assert_includes response.body, "Revoked"
    assert_select %(form[action="/recording_studio_api/api_clients/#{api_client.id}/tokens/#{token.id}/revoke?close_url=%2F"] button), count: 0
  end

  test "show does not render token count rows" do
    api_client = create_api_client_for(parent_recording: @workspace_root_recording, name: "Activity API client")
    latest_credential = api_client.credentials.max_by(&:created_at)

    RecordingStudioApi::ApiAccessToken.create!(
      credential: latest_credential,
      token_digest: "access_digest_#{SecureRandom.hex(16)}",
      token_prefix: "acc",
      expires_at: 2.days.from_now,
      last_used_at: 1.hour.ago
    )

    get "/recording_studio_api/api_clients/#{api_client.id}"

    assert_response :success
    assert_not_includes response.body, "Issued tokens"
    assert_not_includes response.body, "Active tokens"
    assert_not_includes response.body, "Revoked tokens"
    assert_not_includes response.body, "OAuth2 activity"
    assert_not_includes response.body, "Active grant sessions"
  end

  test "edit renders form for name and expiry" do
    api_client = create_api_client_for(parent_recording: @workspace_root_recording, name: "Editable API client")

    get "/recording_studio_api/api_clients/#{api_client.id}/edit"

    assert_response :success
    assert_includes response.body, "Edit API access"
    assert_includes response.body, "Name"
    assert_includes response.body, "Expires"
    assert_includes response.body, "Save changes"
    assert_select %(nav.flat-pack-page-nav a[href="/"][aria-label="Close"]), count: 1
    assert_select %(form[action="/recording_studio_api/api_clients/#{api_client.id}?close_url=%2F"]), count: 1
  end

  test "show returns not found for unknown API client" do
    get "/recording_studio_api/api_clients/non-existent-client"

    assert_response :not_found
  end

  test "update rejects invalid expiry value" do
    api_client = create_api_client_for(parent_recording: @workspace_root_recording, name: "Original API client")

    patch "/recording_studio_api/api_clients/#{api_client.id}", params: {
      api_client: {
        role: "admin",
        api_client_name: "Still valid",
        expires_at: "invalid-datetime"
      }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "Expiry must be a valid date and time"
  end

  test "update rejects invalid role" do
    api_client = create_api_client_for(parent_recording: @workspace_root_recording, name: "Original API client")

    patch "/recording_studio_api/api_clients/#{api_client.id}", params: {
      api_client: {
        role: "owner",
        api_client_name: "Still invalid",
        expires_at: ""
      }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "Role is invalid"
  end

  test "update changes api client name and latest credential expiry" do
    api_client = create_api_client_for(parent_recording: @workspace_root_recording, name: "Original API client")
    latest_credential = api_client.credentials.max_by(&:created_at)
    new_expires_at = 14.days.from_now.change(sec: 0)

    patch "/recording_studio_api/api_clients/#{api_client.id}", params: {
      api_client: {
        api_client_name: "Renamed API client",
        expires_at: new_expires_at.strftime("%Y-%m-%dT%H:%M")
      }
    }

    assert_redirected_to "/recording_studio_api/api_clients/#{api_client.id}?close_url=%2F"

    assert_equal "Renamed API client", api_client.reload.name
    assert_in_delta new_expires_at.to_i, latest_credential.reload.expires_at.to_i, 60
  end

  private

  def create_api_client_for(parent_recording:, name:, role: :admin)
    manager_access_recording = with_access_creation_context do
      access = RecordingStudio::Access.create!(actor: @user, role: role)
      RecordingStudio::Recording.create!(recordable: access, parent_recording: parent_recording)
    end

    api_client = RecordingStudioApi::ApiClient.create!(
      name: name,
      access_recording: manager_access_recording
    )

    access_recording = with_access_creation_context do
      access = RecordingStudio::Access.create!(actor: api_client, role: role)
      RecordingStudio::Recording.create!(recordable: access, parent_recording: parent_recording)
    end

    RecordingStudioApi::ApiClient.where(id: api_client.id).update_all(
      access_recording_id: access_recording.id,
      updated_at: Time.current
    )
    api_client.reload

    api_client_recording = RecordingStudio::Recording.create!(
      recordable: api_client,
      parent_recording: access_recording
    )

    api_credential = RecordingStudioApi::ApiCredential.create!(
      api_client: api_client,
      access_recording: access_recording,
      token_public_id: "pub_#{SecureRandom.hex(8)}",
      token_digest: "digest_#{SecureRandom.hex(16)}",
      token_prefix: "api",
      expires_at: 7.days.from_now
    )

    RecordingStudio::Recording.create!(
      recordable: api_credential,
      parent_recording: api_client_recording
    )

    api_client
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