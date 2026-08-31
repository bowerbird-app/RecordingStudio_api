# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "../test_helper"
require_relative "../dummy/config/environment"
require_relative "../support/api_dummy_helpers"

require "devise/test/integration_helpers"
require "rails/test_help"

class HomeControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ApiDummyHelpers

  TEST_PASSWORD = "HomeTestPassword!2026"

  setup do
    configure_dummy_operations_api!
    @user = User.create!(email: "home-test-#{SecureRandom.hex(4)}@example.com") do |user|
      user.password = TEST_PASSWORD
      user.password_confirmation = TEST_PASSWORD
    end

    sign_in @user
  end

  test "root page renders the api access demo with the API admin link" do
    workspace = Workspace.create!(name: "Root Workspace")
    workspace_root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    create_access_recording(parent_recording: workspace_root_recording, user: @user, role: :admin)

    folder = Folder.create!(name: "Root Folder")
    folder_recording = RecordingStudio::Recording.create!(recordable: folder, parent_recording: workspace_root_recording)
    create_access_recording(parent_recording: folder_recording, user: @user, role: :view)

    get root_path

    assert_response :success
    assert_select "h1", text: "Recording Studio API demo"
    assert_includes response.body, "Demo to add and remove API access"
    assert_select "html[data-theme='rounded']", count: 1
    assert_select "body[data-recording-studio-default-layout='true']", count: 1
    assert_select %(a[href="/api?anchor_url=%2F"]), text: "API settings", count: 1
    assert_select %(a[href="/docs/scalar/v1/test-credential"]), text: "Create API test token", count: 1
    assert_not_includes response.body, "API keys"
    assert_not_includes response.body, "Child access recording"
    assert_not_includes response.body, "Open admin"
    assert_not_includes response.body, "Manage users"
    assert_not_includes response.body, "Open tree"
    assert_not_includes response.body, "Current root"
  end

  test "root page shows admin content when admin root is selected" do
    _, admin_root_recording = create_admin_root_recording
    admin_api = RecordingStudioApi::AdminApi.create!(key: "api-#{SecureRandom.hex(4)}", name: "Admin API")
    create_access_recording(parent_recording: admin_root_recording, user: @user, role: :admin)
    RecordingStudio::Recording.create!(recordable: admin_api, parent_recording: admin_root_recording)

    workspace = Workspace.create!(name: "Old Workspace")
    workspace_root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    create_access_recording(parent_recording: workspace_root_recording, user: @user, role: :admin)

    get root_path

    assert_response :success
    assert_select "h1", text: "Admin"
    assert_not_includes response.body, "Recording Studio API demo"
    assert_select "#public-api h2", text: "Public API", count: 1
    assert_select %(a[href="#public-api"][aria-label="Copy link to Public API"]), count: 1
    assert_select %(a[href="/admin/api?anchor_url=%2F"]), text: "Public API Admin dashboard", count: 1
    assert_select %(a[href="/docs/scalar"]), text: "Public API docs", count: 1
    assert_select %(a[href="/docs/scalar/v1/test-credential"]), text: "Create API test token", count: 1
    assert_select "#operations-api h2", text: "Operations API", count: 1
    assert_select %(a[href="#operations-api"][aria-label="Copy link to Operations API"]), count: 1
    assert_select "#operations-api p", text: "Private API for admin use only", count: 1
    assert_select %(a[href="/admin/api/operations"]), text: "Operations API Admin dashboard", count: 1
    assert_select %(a[href="/admin/operations-api/docs"]), text: "Operations API docs", count: 1
    assert_select %(a[href="/admin/operations-api/docs/v1/test-credential"]), text: "Create Operations API test token", count: 1
    assert_includes response.body, "Operations API docs"
    assert_not_includes response.body, "API keys"
  end

  test "operations test token page issues an operations-scoped token" do
    _, admin_root_recording = create_admin_root_recording
    create_access_recording(parent_recording: admin_root_recording, user: @user, role: :admin)

    workspace = Workspace.create!(name: "Public-only token scope")
    workspace_recording = RecordingStudio::Recording.create!(recordable: workspace)
    create_access_recording(parent_recording: workspace_recording, user: @user, role: :admin)

    get operations_api_scalar_test_credential_path(version: "v1")

    assert_response :success
    assert_select %(body[data-recording-studio-default-layout="true"]), count: 1
    assert_select "h1", text: "Operations API test token"
    assert_select %(form[action="#{operations_api_scalar_test_credential_path(version: 'v1')}"]), count: 1
    assert_select %(select[name="access_point_recording_id"]), count: 1
    assert_select %(select[name="role"]), count: 1
    assert_select %(button[type="submit"]), text: "Generate token", count: 1
    assert_includes response.body, "Admin root: Admin"
    assert_not_includes response.body, "Workspace: Public-only token scope"

    post operations_api_scalar_test_credential_path(version: "v1"), params: {
      access_point_recording_id: workspace_recording.id,
      role: "view"
    }

    assert_redirected_to operations_api_scalar_test_credential_path(version: "v1")
    assert_not RecordingStudioApi::ApiClient.exists?(api_key: "operations")

    post operations_api_scalar_test_credential_path(version: "v1"), params: {
      access_point_recording_id: admin_root_recording.id,
      role: "view"
    }

    assert_redirected_to operations_api_scalar_test_credential_path(version: "v1")
    assert_equal "operations", RecordingStudioApi::ApiClient.order(created_at: :desc).first.api_key

    follow_redirect!

    assert_response :success
    assert_includes response.body, "Operations API test bearer token issued."
    assert_includes response.body, "Bearer rsapi_at_"
  end

  test "standard workspace sidebar omits operations administration links" do
    workspace = Workspace.create!(name: "Public API Workspace")
    workspace_root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    create_access_recording(parent_recording: workspace_root_recording, user: @user, role: :admin)

    get root_path

    assert_response :success
    assert_select %(a[href="/admin/api/operations"]), count: 0
    assert_select %(a[href="/admin/operations-api/docs"]), count: 0
    assert_select %(a[href="/admin/operations-api/docs/v1/test-credential"]), count: 0

    get operations_api_scalar_test_credential_path(version: "v1")

    assert_response :forbidden
  end

  test "operations Scalar docs require the operations admin workspace" do
    _, admin_root_recording = create_admin_root_recording
    create_access_recording(parent_recording: admin_root_recording, user: @user, role: :admin)

    get "/admin/operations-api/docs/v1"

    assert_response :success
    assert_select %(body[data-recording-studio-default-layout="true"]), count: 1
    assert_select "#scalar-api-reference", text: "Loading API documentation...", count: 1
    assert_select "#scalar-api-reference-source[src^='/assets/recording_studio_api/scalar-1.64.0']", count: 1
    assert_select "#scalar-api-reference-source[src^='http']", count: 0
    assert_select %(a[href="/admin/operations-api/docs/v1/fullscreen"]), text: "Full width"
    assert_includes response.body, 'source.addEventListener("load", initializeScalar'
    assert_includes response.body, '"url":"/admin/operations-api/docs/v1/openapi.json"'

    get "/admin/operations-api/docs/v1/openapi.json"

    assert_response :success, response.body
    paths = JSON.parse(response.body).fetch("paths").keys
    assert_includes paths, "/recording_studio_api/apis/operations/v1/admin_roots"
    assert_not_includes paths, "/recording_studio_api/api/v1/workspaces"

    workspace = Workspace.create!(name: "Non-admin docs workspace")
    workspace_root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    create_access_recording(parent_recording: workspace_root_recording, user: @user, role: :admin)
    switch_to_root(workspace_root_recording)

    get "/admin/operations-api/docs/v1"

    assert_response :forbidden

    get "/admin/operations-api/docs/v1/fullscreen"

    assert_response :forbidden

    get "/admin/operations-api/docs/v1/openapi.json"

    assert_response :forbidden
  end

  test "workspace page renders its child recordings tree" do
    workspace = Workspace.create!(name: "Demo Workspace")
    root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    folder = Folder.create!(name: "Access Folder")
    folder_recording = RecordingStudio::Recording.create!(recordable: folder, parent_recording: root_recording)
    page = Page.create!(title: "Access Page")
    RecordingStudio::Recording.create!(recordable: page, parent_recording: folder_recording)

    get workspace_path

    assert_response :success
    assert_select "h1", text: "Workspace"
    assert_includes response.body, "Child recordings attached to the workspace access root."
    assert_includes response.body, "Workspace: Demo Workspace"
    assert_includes response.body, "Folder: Access Folder"
    assert_includes response.body, "Page: Access Page"
    assert_not_includes response.body, "No workspace recordings found."
  end

  test "folder page renders its child recordings tree" do
    folder = Folder.create!(name: "Demo Folder")
    root_recording = RecordingStudio::Recording.create!(recordable: folder)
    page = Page.create!(title: "Folder Child Page")
    RecordingStudio::Recording.create!(recordable: page, parent_recording: root_recording)

    get folder_path

    assert_response :success
    assert_select "h1", text: "Folder"
    assert_includes response.body, "Child recordings attached to the folder access root."
    assert_includes response.body, "Folder: Demo Folder"
    assert_includes response.body, "Page: Folder Child Page"
    assert_not_includes response.body, "No folder recordings found."
  end

  test "root switch page uses the Recording Studio default layout when admin root is current" do
    _, admin_root_recording = create_admin_root_recording
    create_access_recording(parent_recording: admin_root_recording, user: @user, role: :admin)

    get recording_studio_root_switchable.root_switch_path(
      scope: "all_roots",
      return_to: root_path
    )

    assert_response :success
    assert_includes response.body, 'data-recording-studio-default-layout="true"'
    assert_includes response.body, "Switch"
    assert_includes response.body, "Admin"
  end

  test "switching from admin to workspace returns to the host root demo" do
    _, admin_root_recording = create_admin_root_recording
    create_access_recording(parent_recording: admin_root_recording, user: @user, role: :admin)

    workspace = Workspace.create!(name: "Studio Workspace")
    workspace_root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    create_access_recording(parent_recording: workspace_root_recording, user: @user, role: :admin)

    patch recording_studio_root_switchable.root_switch_path(scope: "all_roots"), params: {
      root_switch: {
        root_recording_id: workspace_root_recording.id,
        return_to: root_path
      }
    }

    assert_redirected_to "/"

    follow_redirect!

    assert_response :success
    assert_select "h1", text: "Recording Studio API demo"
    assert_includes response.body, "Demo to add and remove API access"
    assert_not_includes response.body, "<h1>Admin</h1>"
  end

  test "switching from a nested root switch return target falls back to the host root demo" do
    _, admin_root_recording = create_admin_root_recording
    create_access_recording(parent_recording: admin_root_recording, user: @user, role: :admin)

    workspace = Workspace.create!(name: "Studio Workspace")
    workspace_root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    create_access_recording(parent_recording: workspace_root_recording, user: @user, role: :admin)

    nested_return_to = recording_studio_root_switchable.root_switch_path(
      scope: "all_roots",
      return_to: "/admin/api"
    )

    patch recording_studio_root_switchable.root_switch_path(scope: "all_roots"), params: {
      root_switch: {
        root_recording_id: workspace_root_recording.id,
        return_to: nested_return_to
      }
    }

    assert_redirected_to "/"

    follow_redirect!

    assert_response :success
    assert_select "h1", text: "Recording Studio API demo"
    assert_includes response.body, "Demo to add and remove API access"
    assert_not_includes response.body, "Change root"
  end

  private

  def switch_to_root(root_recording)
    patch recording_studio_root_switchable.root_switch_path(scope: "all_roots"), params: {
      root_switch: {
        root_recording_id: root_recording.id,
        return_to: root_path
      }
    }
  end

end