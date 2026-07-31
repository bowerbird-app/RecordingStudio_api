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
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!

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
    assert_includes response.body, "Create API key"
    assert_includes response.body, "Create"
    assert_includes response.body, "Access point"
    assert_includes response.body, "Name"
    assert_includes response.body, "Role"
    assert_includes response.body, "Controls what this API key can access and change"
    assert_includes response.body, "Expires"
    assert_select %(input[name="api_client[expires_at]"][placeholder="Never"]), count: 1
    assert_not_includes response.body, "Access role"
    assert_not_includes response.body, "Credential expiry"
    assert_not_includes response.body, "Top-level recording"
    assert_not_includes response.body, "access_request_root_recording_id"
    assert_not_includes response.body, "Workspace root"
    assert_not_includes response.body, "Boundary minimum role"
  end

  test "renders api access point choices below the requested root recording" do
    folder_recording = RecordingStudio::Recording.create!(
      recordable: Folder.create!(name: "API Access Folder"),
      parent_recording: @workspace_root_recording
    )
    page_recording = create_page_recording(root_recording: @workspace_root_recording, page_title: "Hidden API Page")

    get "/recording_studio_api/api_clients/new", params: { root_recording_id: @workspace_root_recording.id }

    assert_response :success
    assert_select %(input[type="hidden"][name="api_client[root_recording_id]"][value="#{@workspace_root_recording.id}"]), count: 1
    assert_includes response.body, "UI Workspace"
    assert_includes response.body, "API Access Folder"
    assert_not_includes response.body, "Hidden API Page"
    assert_not_includes response.body, page_recording.id
    assert_includes response.body, folder_recording.id
  end

  test "hides accessible recordings that are not api access point capable" do
    folder_recording = RecordingStudio::Recording.create!(
      recordable: Folder.create!(name: "Non API Access Folder"),
      parent_recording: @workspace_root_recording
    )
    original_capability_enabled = RecordingStudio.method(:capability_enabled?)

    RecordingStudio.stub(:capability_enabled?, lambda do |capability, **kwargs|
      next false if capability == :api_access_point && kwargs[:for] == "Folder"

      original_capability_enabled.call(capability, **kwargs)
    end) do
      get "/recording_studio_api/api_clients/new", params: { root_recording_id: @workspace_root_recording.id }
    end

    assert_response :success
    assert_includes response.body, "UI Workspace"
    assert_not_includes response.body, "Non API Access Folder"
    assert_not_includes response.body, folder_recording.id
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
    assert_secret_response_not_stored
    assert_secret_reveal_scrubber_present
    assert_select %(nav.flat-pack-page-nav a[href="/"][aria-label="Close"]), count: 1
    assert_includes response.body, "Copy secret"
    assert_includes response.body, "This is only shown once. Use it to access the API."
    assert_includes response.body, "Finish"
    assert_not_includes response.body, "Back to demo"
    assert_not_includes response.body, "Add another"
    assert_not_includes response.body, "Root recording"
    assert_not_includes response.body, "Access point"
    assert_not_includes response.body, "Access role"
    assert_not_includes response.body, "Client ID"
    assert_not_includes response.body, "Credential expiry"
    assert_not_includes response.body, "Client secret"

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

  test "creates credentials for the selected named API" do
    RecordingStudioApi.configuration.api(:operations)
    RecordingStudioApi.register_recordable_type_api("Workspace", api: :operations)

    post "/recording_studio_api/api_clients", params: {
      api_client: {
        api_key: "operations",
        root_type: "Workspace",
        access_point_recording_id: @workspace_root_recording.id,
        role: "admin",
        api_client_name: "Operations UI client",
        expires_at: ""
      }
    }

    assert_response :created
    assert_equal "operations", RecordingStudioApi::ApiClient.find_by!(name: "Operations UI client").api_key
  end

  test "index lists API access including descendant child access" do
    direct_api_client = create_api_client_for(
      parent_recording: @workspace_root_recording,
      name: "Direct API client"
    )
    direct_oauth_client_id = direct_api_client.credentials.max_by(&:created_at).oauth_client_id
    direct_expires_at = direct_api_client.credentials.max_by(&:created_at).expires_at.in_time_zone

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
    assert_not_includes response.body, "Most used keys"
    assert_not_includes response.body, "Total API keys"
    assert_includes response.body, "API access below Workspace: UI Workspace."
    assert_includes response.body, "Name"
    assert_includes response.body, "API key"
    assert_includes response.body, "Access point"
    assert_includes response.body, "Expires"
    assert_select "th", text: "Root", count: 0
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
    assert_match(/(\d+\s+(minute|minutes|hour|hours|day|days|week|weeks|month|months|year|years)\s+ago|In\s+\d+\s+(minute|minutes|hour|hours|day|days|week|weeks|month|months|year|years))/, response.body)
    assert_includes response.body, %(datetime="#{direct_expires_at.iso8601}")
    expected_day_labels = (6.days.ago.to_date..Date.current).map { |day| day.strftime("%a") }
    expected_day_labels.each do |day_label|
      assert_includes response.body, day_label
    end
    assert_includes response.body, 'class="flat-pack-timestamp'
  end

  test "index hides request charts when there are no api keys yet" do
    get "/recording_studio_api/api_clients", params: { root_recording_id: @workspace_root_recording.id, close_url: "/workspace" }

    assert_response :success
    assert_not_includes response.body, "Most used keys"
    assert_not_includes response.body, "Full screen"
    assert_not_includes response.body, "API requests"
    assert_not_includes response.body, "Total API keys"
  end

  test "requests chart page renders full-screen chart and links back to api clients" do
    get "/recording_studio_api/api_clients/requests_chart", params: {
      root_recording_id: @workspace_root_recording.id,
      close_url: "/workspace"
    }

    assert_response :success
    assert_includes response.body, "API requests"
    assert_match(/\[(\s*0\s*,){29}\s*0\s*\]/, response.body)
    assert_select "turbo-frame#requests-chart-frame", count: 1
    assert_includes response.body, "flat-pack--auto-submit"
    assert_includes response.body, "All API keys"
    assert_includes response.body, "All statuses"
    assert_select %(input[type="hidden"][name="api_client_id"]), count: 1
    assert_select %(button[data-action="flat-pack--select#toggle"]), minimum: 1
    assert_select %(select[name="status"] option[value=""]:not([disabled])), text: "All statuses", count: 1
    assert_select %(nav.flat-pack-page-nav a[href="/workspace"][aria-label="Close"]), count: 1
  end

  # rubocop:disable Metrics/BlockLength
  test "requests chart filters series by date range status and api key within the scoped recordings" do
    api_client = create_api_client_for(parent_recording: @workspace_root_recording, name: "Filtered chart client")

    nested_folder_recording = RecordingStudio::Recording.create!(
      recordable: Folder.create!(name: "Requests chart nested folder"),
      parent_recording: @workspace_root_recording
    )

    nested_api_client = create_api_client_for(parent_recording: nested_folder_recording, name: "Nested chart client")

    outside_workspace = Workspace.create!(name: "Outside Workspace")
    outside_root_recording = RecordingStudio::Recording.create!(recordable: outside_workspace)
    outside_api_client = create_api_client_for(parent_recording: outside_root_recording, name: "Outside chart client")

    ensure_api_request_logs_table!

    RecordingStudioApi::ApiRequestLog.where(api_client_id: [api_client.id, nested_api_client.id, outside_api_client.id]).delete_all

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

      RecordingStudioApi::ApiRequestLog.create!(
        occurred_at: request_date.in_time_zone.change(hour: 12),
        request_id: "chart-filter-nested-#{index}",
        request_method: "GET",
        request_path: "/api/v1/recordings",
        status_code: 200,
        duration_ms: 50,
        api_client_id: nested_api_client.id,
        api_credential_id: nested_api_client.credentials.max_by(&:created_at).id,
        access_recording_id: nested_api_client.access_recording_id,
        root_recording_id: @workspace_root_recording.id
      )

      RecordingStudioApi::ApiRequestLog.create!(
        occurred_at: request_date.in_time_zone.change(hour: 14),
        request_id: "chart-filter-outside-#{index}",
        request_method: "GET",
        request_path: "/api/v1/recordings",
        status_code: 200,
        duration_ms: 55,
        api_client_id: outside_api_client.id,
        api_credential_id: outside_api_client.credentials.max_by(&:created_at).id,
        access_recording_id: outside_api_client.access_recording_id,
        root_recording_id: outside_root_recording.id
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
      parent_recording_id: @workspace_root_recording.id,
      include_children: "1",
      api_client_id: api_client.id,
      start_date: 2.days.ago.to_date.iso8601,
      end_date: Date.current.iso8601,
      status: "success"
    }

    assert_response :success
    assert_match(/\[\s*1\s*,\s*1\s*,\s*1\s*\]/, response.body)
    refute_match(/\[\s*1\s*,\s*2\s*,\s*1\s*\]/, response.body)
    refute_match(/\[\s*2\s*,\s*2\s*,\s*2\s*\]/, response.body)
    assert_includes response.body, "value=\"success\""
    assert_includes response.body, "Filtered chart client"
    assert_includes response.body, "Nested chart client"
    assert_not_includes response.body, "Outside chart client"
    assert_select %(input[type="hidden"][name="api_client_id"][value="#{api_client.id}"]), count: 1
    assert_select %(div[role="option"][data-value="#{nested_api_client.id}"]), text: /Nested chart client/
    assert_select %(div[role="option"][data-value="#{outside_api_client.id}"]), count: 0
    assert_select %(select[name="status"] option[value=""]:not([disabled])), text: "All statuses", count: 1
  end
  # rubocop:enable Metrics/BlockLength

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

  test "index parent scope includes descendants by default" do
    direct_api_client = create_api_client_for(
      parent_recording: @workspace_root_recording,
      name: "Root default scope client"
    )

    nested_folder_recording = RecordingStudio::Recording.create!(
      recordable: Folder.create!(name: "Default include folder"),
      parent_recording: @workspace_root_recording
    )

    nested_api_client = create_api_client_for(
      parent_recording: nested_folder_recording,
      name: "Nested default scope client"
    )

    get "/recording_studio_api/api_clients", params: {
      root_recording_id: @workspace_root_recording.id,
      parent_recording_id: @workspace_root_recording.id
    }

    assert_response :success
    assert_includes response.body, direct_api_client.name
    assert_includes response.body, nested_api_client.name
  end

  test "index parent scope can exclude descendants" do
    direct_api_client = create_api_client_for(
      parent_recording: @workspace_root_recording,
      name: "Root only scope client"
    )

    nested_folder_recording = RecordingStudio::Recording.create!(
      recordable: Folder.create!(name: "Exclude children folder"),
      parent_recording: @workspace_root_recording
    )

    nested_api_client = create_api_client_for(
      parent_recording: nested_folder_recording,
      name: "Nested excluded client"
    )

    get "/recording_studio_api/api_clients", params: {
      root_recording_id: @workspace_root_recording.id,
      parent_recording_id: @workspace_root_recording.id,
      include_children: "0"
    }

    assert_response :success
    assert_includes response.body, direct_api_client.name
    assert_not_includes response.body, nested_api_client.name
  end

  test "index scope params require accessible recordings" do
    outsider_user = create_user(email: "scope-outsider@example.com")
    outsider_root_recording, = create_access_recording_for(user: outsider_user, role: :admin)

    get "/recording_studio_api/api_clients", params: { root_recording_id: outsider_root_recording.id }
    assert_response :forbidden

    get "/recording_studio_api/api_clients", params: { parent_recording_id: outsider_root_recording.id }
    assert_response :forbidden
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
    assert_select %(a[href="/recording_studio_api/api_clients/#{api_client.id}/tokens?close_url=%2F"]), count: 0
    assert_select %(a[href="/recording_studio_api/api_clients/#{api_client.id}/log?close_url=%2F"]), count: 0
    assert_not_includes response.body, "Create a new secret and api key"
    assert_not_includes response.body, "Rotated keys"
    assert_select %(a[href="/recording_studio_api/api_clients/#{api_client.id}/rotate?close_url=%2F"]), count: 0
    assert_select %(a[href="/recording_studio_api/api_clients/#{api_client.id}/revoke?close_url=%2F"]), count: 0
    assert_not_includes response.body, "Back to API access list"
    assert_not_includes response.body, "Back to demo"
  end

  test "rotate revokes the latest credential and shows the new secret" do
    api_client = create_api_client_for(parent_recording: @workspace_root_recording, name: "Rotatable API client")
    previous_credential = api_client.credentials.max_by(&:created_at)

    post "/recording_studio_api/api_clients/#{api_client.id}/rotate"

    assert_response :created
    assert_secret_response_not_stored
    assert_secret_reveal_scrubber_present
    assert_includes response.body, "API key rotated"
    assert_includes response.body, "New client secret"
    assert_includes response.body, "New API key"
    assert_includes response.body, "Finish"

    api_client.reload
    new_credential = api_client.credentials.max_by(&:created_at)

    assert_not_equal previous_credential.id, new_credential.id
    assert_not_nil previous_credential.reload.revoked_at
    assert_includes response.body, new_credential.oauth_client_id
  end

  test "show lists rotated keys for older credentials" do
    api_client = create_api_client_for(parent_recording: @workspace_root_recording, name: "Rotated history client")
    previous_credential = api_client.credentials.max_by(&:created_at)

    result = RecordingStudioApi::Services::RotateApiCredential.call(
      api_client: api_client,
      actor: @user
    )

    assert result.success?, result.error

    new_credential = result.value.fetch(:credential)

    get "/recording_studio_api/api_clients/#{api_client.id}"

    assert_response :success
    assert_includes response.body, "Rotated keys"
    assert_includes response.body, "API keys that were rotated and revoked"
    assert_includes response.body, previous_credential.oauth_client_id
    assert_includes response.body, "Revoked"
    assert_includes response.body, "Never used"
    assert_includes response.body, "Never"
    assert_includes response.body, new_credential.oauth_client_id
  end

  test "show revokes the latest credential" do
    api_client = create_api_client_for(parent_recording: @workspace_root_recording, name: "Revocable API client")
    latest_credential = api_client.credentials.max_by(&:created_at)

    post "/recording_studio_api/api_clients/#{api_client.id}/revoke"

    assert_redirected_to "/recording_studio_api/api_clients/#{api_client.id}?close_url=%2F"
    assert_not_nil latest_credential.reload.revoked_at

    get "/recording_studio_api/api_clients/#{api_client.id}"

    assert_response :success
    # badge removed per design; ensure status shows Revoked and revoke link is gone
    assert_includes response.body, "Revoked"
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

  test "update rejects access point ids outside the api client's root" do
    other_root_recording, = create_access_recording_for(
      user: @user,
      workspace_name: "Other Managed Workspace",
      role: :admin
    )
    api_client = create_api_client_for(parent_recording: @workspace_root_recording, name: "Scoped update client")
    access_recording = api_client.access_recording

    patch "/recording_studio_api/api_clients/#{api_client.id}", params: {
      api_client: {
        access_point_recording_id: other_root_recording.id,
        role: "admin",
        api_client_name: "Moved client",
        expires_at: ""
      }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "Access point is invalid"
    assert_equal @workspace_root_recording.id, access_recording.reload.parent_recording_id
    assert_equal "Scoped update client", api_client.reload.name
  end

  test "manager of a different root cannot mutate an api client" do
    api_client = create_api_client_for(parent_recording: @workspace_root_recording, name: "Protected client")
    credential = api_client.credentials.max_by(&:created_at)
    other_user = create_user(email: "other-manager@example.com")
    create_access_recording_for(user: other_user, workspace_name: "Other Manager Workspace", role: :admin)

    sign_in other_user

    patch "/recording_studio_api/api_clients/#{api_client.id}", params: {
      api_client: {
        api_client_name: "Cross-root rename",
        expires_at: ""
      }
    }
    assert_response :not_found
    assert_equal "Protected client", api_client.reload.name

    post "/recording_studio_api/api_clients/#{api_client.id}/rotate"
    assert_response :not_found
    assert_nil credential.reload.revoked_at

    post "/recording_studio_api/api_clients/#{api_client.id}/revoke"
    assert_response :not_found
    assert_nil credential.reload.revoked_at
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
    assert_includes response.body, "Edit API key"
    assert_includes response.body, "Name"
    assert_includes response.body, "Advanced"
    assert_includes response.body, "Role"
    assert_includes response.body, "Expires"
    assert_includes response.body, "Access point"
    assert_includes response.body, "Save changes"
    assert_includes response.body, "Create a new secret and api key"
    assert_select %(a[href="/recording_studio_api/api_clients/#{api_client.id}/rotate?close_url=%2F"][data-turbo-method="post"][data-turbo-confirm="Rotate this API key? This will revoke the current key."]), text: "Rotate key"
    assert_select %(a[href="/recording_studio_api/api_clients/#{api_client.id}/revoke?close_url=%2F"][data-turbo-method="post"][data-turbo-confirm="Revoke this API key?"]), text: "Revoke"
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

  test "edit managers cannot create or assign admin API access" do
    RecordingStudio::Access.where(id: @workspace_access_recording.recordable_id).update_all(role: "edit")
    RecordingStudioApi.configuration.access_management_edit_role = :edit

    post "/recording_studio_api/api_clients", params: {
      api_client: {
        root_type: "Workspace",
        access_point_recording_id: @workspace_root_recording.id,
        role: "admin",
        api_client_name: "Escalated client",
        expires_at: ""
      }
    }

    assert_response :unprocessable_entity
    assert_equal 0, RecordingStudioApi::ApiClient.where(name: "Escalated client").count

    api_client = create_api_client_for(parent_recording: @workspace_root_recording, name: "Editable client", role: :edit)

    patch "/recording_studio_api/api_clients/#{api_client.id}", params: {
      api_client: {
        role: "admin",
        api_client_name: "Escalated update",
        expires_at: ""
      }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "Requested API access role exceeds your access"
    assert_equal "edit", api_client.access_recording.reload.recordable.role
    assert_equal "Editable client", api_client.reload.name
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

  def assert_secret_response_not_stored
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_includes response.headers["Cache-Control"], "private"
    assert_equal "no-cache", response.headers["Pragma"]
    assert_equal "0", response.headers["Expires"]
  end

  def assert_secret_reveal_scrubber_present
    assert_select %(pre[data-secret-reveal-target="secret"]), count: 1
    assert_includes response.body, "pagehide"
    assert_includes response.body, "turbo:before-cache"
    assert_includes response.body, "Secret hidden after leaving this page."
  end

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