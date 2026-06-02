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
    assert_includes response.body, "Add API access"
    assert_includes response.body, "Create access"
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
    assert_not_includes response.body, access_recording.root_recording_id.to_s
  end

  test "index lists API access including descendant child access" do
    direct_api_client = create_api_client_for(
      parent_recording: @workspace_root_recording,
      name: "Direct API client"
    )

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
    assert_includes response.body, "API access list"
    assert_includes response.body, "API access below Workspace: UI Workspace."
    assert_includes response.body, "Name"
    assert_includes response.body, "Access point"
    assert_includes response.body, "Expires"
    assert_not_includes response.body, "Root"
    assert_not_includes response.body, "Access recording"
    assert_not_includes response.body, "Details"
    assert_includes response.body, direct_api_client.name
    assert_includes response.body, "Workspace"
    assert_includes response.body, nested_api_client.name
    assert_includes response.body, "Nested Folder"
    assert_select %(a[href="/recording_studio_api/api_clients/#{direct_api_client.id}?close_url=%2Fworkspace"]), text: direct_api_client.name
    assert_select %(a[href="/recording_studio_api/api_clients/#{nested_api_client.id}?close_url=%2Fworkspace"]), text: nested_api_client.name
  end

  test "page nav falls back to the default close url when close url is unsafe" do
    get "/recording_studio_api/api_clients/new", params: { root_type: "Workspace", close_url: "https://example.com/escape" }

    assert_response :success
    assert_select %(nav.flat-pack-page-nav a[href="/"][aria-label="Close"]), count: 1
    assert_not_includes response.body, "https://example.com/escape"
  end

  test "view-only access can see api access but cannot change it" do
    view_user = create_user(email: "view-access@example.com")
    sign_out @user
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
    masked_oauth_client_id = "#{oauth_client_id.first(2)}#{"*" * (oauth_client_id.length - 4)}#{oauth_client_id.last(2)}"

    get "/recording_studio_api/api_clients/#{api_client.id}"

    assert_response :success
    assert_select %(nav.flat-pack-page-nav a[href="/"][aria-label="Close"]), count: 1
    assert_includes response.body, "Details API client"
    assert_includes response.body, "Field"
    assert_includes response.body, "Value"
    assert_includes response.body, "Actions"
    assert_includes response.body, "Name"
    assert_includes response.body, "API key"
    assert_includes response.body, masked_oauth_client_id
    assert_not_includes response.body, oauth_client_id
    assert_includes response.body, "API secret"
    assert_includes response.body, "Hidden after creation"
    assert_includes response.body, "Role"
    assert_includes response.body, "Expiry"
    assert_includes response.body, "Machine token health"
    assert_includes response.body, "OAuth2 activity"
    assert_includes response.body, "Issued tokens"
    assert_includes response.body, "Active grant sessions"
    assert_select %(div#machine-token-health[data-controller="flat-pack--section-title-anchor"]), count: 1
    assert_select %(a[href="#machine-token-health"][data-flat-pack--section-title-anchor-target="link"]), count: 1
    assert_select %(div#oauth2-activity[data-controller="flat-pack--section-title-anchor"]), count: 1
    assert_select %(a[href="#oauth2-activity"][data-flat-pack--section-title-anchor-target="link"]), count: 1
    assert_select %(form[action="/recording_studio_api/api_clients/#{api_client.id}/edit?close_url=%2F"] button), text: "Edit"
    assert_select %(form[action="/recording_studio_api/api_clients/#{api_client.id}/tokens?close_url=%2F"] button), text: "Tokens"
    assert_not_includes response.body, "Back to API access list"
    assert_not_includes response.body, "Back to demo"
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

  test "show renders token and oauth activity counts with session link" do
    api_client = create_api_client_for(parent_recording: @workspace_root_recording, name: "Activity API client")
    latest_credential = api_client.credentials.max_by(&:created_at)
    access_recording = api_client.access_recording

    RecordingStudioApi::ApiAccessToken.create!(
      credential: latest_credential,
      token_digest: "access_digest_#{SecureRandom.hex(16)}",
      token_prefix: "acc",
      expires_at: 2.days.from_now,
      last_used_at: 1.hour.ago
    )

    oauth_client = RecordingStudioApi::OauthClient.create!(
      name: "Mobile app",
      client_identifier: "client_#{SecureRandom.hex(8)}",
      redirect_uri: "https://example.com/callback",
      public_client: true,
      active: true
    )

    oauth_session = RecordingStudioApi::OauthGrantSession.create!(
      oauth_client: oauth_client,
      access_recording: access_recording,
      last_used_at: 30.minutes.ago
    )

    RecordingStudioApi::OauthSessionAccessToken.create!(
      oauth_grant_session: oauth_session,
      token_digest: "oauth_access_digest_#{SecureRandom.hex(16)}",
      token_prefix: "oat",
      expires_at: 1.day.from_now,
      last_used_at: 20.minutes.ago
    )

    RecordingStudioApi::OauthRefreshToken.create!(
      oauth_grant_session: oauth_session,
      token_digest: "oauth_refresh_digest_#{SecureRandom.hex(16)}",
      token_prefix: "ort",
      expires_at: 14.days.from_now,
      last_used_at: 10.minutes.ago
    )

    RecordingStudioApi::OauthAuthorizationCode.create!(
      oauth_client: oauth_client,
      access_recording: access_recording,
      code_digest: "code_digest_#{SecureRandom.hex(16)}",
      code_prefix: "oc",
      code_challenge: "challenge",
      code_challenge_method: "S256",
      redirect_uri: "https://example.com/callback",
      expires_at: 5.minutes.from_now,
      consumed_at: Time.current
    )

    get "/recording_studio_api/api_clients/#{api_client.id}"

    assert_response :success
    assert_select "td", text: "Issued tokens"
    assert_select "td", text: "Active grant sessions"
    assert_match(/Issued tokens<\/td>\s*<td[^>]*>1<\/td>/, response.body)
    assert_match(/Active grant sessions<\/td>\s*<td[^>]*>1<\/td>/, response.body)
    assert_match(/Active OAuth access tokens<\/td>\s*<td[^>]*>1<\/td>/, response.body)
    assert_match(/Active refresh tokens<\/td>\s*<td[^>]*>1<\/td>/, response.body)
    assert_match(/Auth codes consumed \(7d\)<\/td>\s*<td[^>]*>1<\/td>/, response.body)
    assert_select %(a[href="/recording_studio_api/oauth_grant_sessions?access_recording_id=#{access_recording.id}"]), text: "View sessions", count: 1
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
    access = RecordingStudio::Access.create!(actor: @user, role: role)
    access_recording = RecordingStudio::Recording.create!(recordable: access, parent_recording: parent_recording)

    api_client = RecordingStudioApi::ApiClient.create!(
      name: name,
      access_recording: access_recording
    )

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
end