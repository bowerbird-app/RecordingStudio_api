# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "../test_helper"
require_relative "../dummy/config/environment"

require "devise/test/integration_helpers"
require "rails/test_help"
require "securerandom"

class AccessRequestsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  TEST_PASSWORD = "AccessRequestPassword!2026"

  setup do
    @user = User.find_or_create_by!(email: "access-requests@example.com") do |user|
      user.password = TEST_PASSWORD
      user.password_confirmation = TEST_PASSWORD
    end

    sign_in @user

    workspace = Workspace.create!(name: "UI Workspace")
    @workspace_root_recording = RecordingStudio::Recording.create!(recordable: workspace)
  end

  test "renders the workspace access request form" do
    get "/recording_studio_api/access_requests/new", params: { root_type: "Workspace" }

    assert_response :success
    assert_includes response.body, "flat-pack-breadcrumb"
    assert_includes response.body, "Add API access"
    assert_includes response.body, "Create access"
    assert_includes response.body, "Name"
    assert_includes response.body, "Role"
    assert_includes response.body, "Expires"
    assert_not_includes response.body, "Access role"
    assert_not_includes response.body, "Credential expiry"
    assert_not_includes response.body, "Top-level recording"
    assert_not_includes response.body, "access_request_root_recording_id"
    assert_not_includes response.body, "Workspace root"
    assert_not_includes response.body, "Boundary minimum role"
  end

  test "submitting the form creates the access hierarchy and shows the client secret" do
    post "/recording_studio_api/access_requests", params: {
      access_request: {
        root_type: "Workspace",
        role: "admin",
        api_client_name: "UI provisioned client",
        expires_at: ""
      }
    }

    assert_response :created
    assert_includes response.body, "flat-pack-breadcrumb"
    assert_includes response.body, "Workspace API access created"
    assert_includes response.body, "UI provisioned client"
    assert_includes response.body, "Client secret"

    api_client = RecordingStudioApi::ApiClient.order(:created_at, :id).last
    access_recording = api_client.access_recording
    eligible_workspace_root_ids = RecordingStudio::Recording.where(parent_recording_id: nil, recordable_type: "Workspace").pluck(:id)

    assert_not_nil access_recording
    assert_includes eligible_workspace_root_ids, access_recording.root_recording_id
    assert_equal "RecordingStudio::Access", access_recording.recordable_type
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

    get "/recording_studio_api/access_requests", params: { root_recording_id: @workspace_root_recording.id }

    assert_response :success
    assert_includes response.body, "flat-pack-breadcrumb"
    assert_includes response.body, "API access list"
    assert_includes response.body, "Showing API access for UI Workspace."
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
    assert_select %(nav.flat-pack-breadcrumb a), text: "Back", count: 1
    assert_select %(nav.flat-pack-breadcrumb a[href="/"]), text: "Back", count: 1
    assert_select %(nav.flat-pack-breadcrumb a[href="/"]), text: "Home", count: 1
    assert_select %(a[href="/recording_studio_api/access_requests/#{direct_api_client.id}"]), text: direct_api_client.name
    assert_select %(a[href="/recording_studio_api/access_requests/#{nested_api_client.id}"]), text: nested_api_client.name
  end

  test "index subtitle shows folder name when scoped to a folder root" do
    folder = Folder.create!(name: "Scoped Folder")
    folder_root_recording = RecordingStudio::Recording.create!(recordable: folder)
    api_client = create_api_client_for(parent_recording: folder_root_recording, name: "Folder scoped client")

    get "/recording_studio_api/access_requests", params: { root_recording_id: folder_root_recording.id }

    assert_response :success
    assert_includes response.body, "Showing API access for Scoped Folder."
    assert_includes response.body, api_client.name
  end

  test "index shows empty state when no access has been given yet" do
    RecordingStudioApi::ApiCredential.delete_all
    RecordingStudioApi::ApiClient.delete_all

    get "/recording_studio_api/access_requests"

    assert_response :success
    assert_includes response.body, "No API access given yet"
    assert_includes response.body, "Create API access from the demo home page to populate this list."
  end

  test "show renders API access details" do
    api_client = create_api_client_for(parent_recording: @workspace_root_recording, name: "Details API client")
    oauth_client_id = api_client.credentials.max_by(&:created_at).oauth_client_id
    masked_oauth_client_id = "#{oauth_client_id.first(2)}#{"*" * (oauth_client_id.length - 4)}#{oauth_client_id.last(2)}"

    get "/recording_studio_api/access_requests/#{api_client.id}"

    assert_response :success
    assert_includes response.body, "flat-pack-breadcrumb"
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
    assert_select %(nav.flat-pack-breadcrumb a[href="/recording_studio_api/access_requests?include_children=1"]), text: "Back", count: 1
    assert_select %(nav.flat-pack-breadcrumb a[href="/"]), text: "Home", count: 1
    assert_select %(form[action="/recording_studio_api/access_requests/#{api_client.id}/edit"] button), text: "Edit"
    assert_not_includes response.body, "Back to API access list"
    assert_not_includes response.body, "Back to demo"
  end

  test "edit renders form for name and expiry" do
    api_client = create_api_client_for(parent_recording: @workspace_root_recording, name: "Editable API client")

    get "/recording_studio_api/access_requests/#{api_client.id}/edit"

    assert_response :success
    assert_includes response.body, "Edit API access"
    assert_includes response.body, "Name"
    assert_includes response.body, "Expires"
    assert_includes response.body, "Save changes"
    assert_select %(nav.flat-pack-breadcrumb a[href="/recording_studio_api/access_requests/#{api_client.id}"]), text: "Back", count: 1
    assert_select %(nav.flat-pack-breadcrumb a[href="/"]), text: "Home", count: 1
  end

  test "update changes api client name and latest credential expiry" do
    api_client = create_api_client_for(parent_recording: @workspace_root_recording, name: "Original API client")
    latest_credential = api_client.credentials.max_by(&:created_at)
    new_expires_at = 14.days.from_now.change(sec: 0)

    patch "/recording_studio_api/access_requests/#{api_client.id}", params: {
      access_request: {
        api_client_name: "Renamed API client",
        expires_at: new_expires_at.strftime("%Y-%m-%dT%H:%M")
      }
    }

    assert_redirected_to "/recording_studio_api/access_requests/#{api_client.id}"

    assert_equal "Renamed API client", api_client.reload.name
    assert_in_delta new_expires_at.to_i, latest_credential.reload.expires_at.to_i, 60
  end

  private

  def create_api_client_for(parent_recording:, name:)
    access = RecordingStudio::Access.create!(actor: @user, role: :admin)
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