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
    @user = User.create!(email: "home-test-#{SecureRandom.hex(4)}@example.com") do |user|
      user.password = TEST_PASSWORD
      user.password_confirmation = TEST_PASSWORD
    end

    sign_in @user
  end

  test "root page renders the api access demo for workspace roots" do
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
    assert_includes response.body, "RecordingStudio API"
    assert_includes response.body, "Workspace"
    assert_includes response.body, "Folder"
    assert_includes response.body, "API keys"
    assert_not_includes response.body, "Child access recording"
    assert_select %(a[href="#{docs_install_path}"]), count: 1
    api_keys_links = Nokogiri::HTML(response.body).css('a[href*="/recording_studio_api/api_clients"]')
    api_keys_query_params = api_keys_links.map do |link|
      uri = URI.parse(link["href"])
      Rack::Utils.parse_nested_query(uri.query.to_s)
    end

    workspace_scope = api_keys_query_params.find do |query_params|
      query_params["root_recording_id"] == query_params["parent_recording_id"]
    end
    refute_nil workspace_scope
    assert_equal "/", workspace_scope.fetch("close_url")
    assert_equal "1", workspace_scope.fetch("include_children")

    folder_scope = api_keys_query_params.find do |query_params|
      query_params["root_recording_id"] != query_params["parent_recording_id"]
    end
    refute_nil folder_scope
    assert_equal "/", folder_scope.fetch("close_url")
    assert_equal "1", folder_scope.fetch("include_children")

    folder_parent_recording = RecordingStudio::Recording.find(folder_scope.fetch("parent_recording_id"))
    assert_equal "Folder", folder_parent_recording.recordable_type
    assert_equal folder_scope.fetch("root_recording_id"), folder_parent_recording.root_recording_id
    assert_not_includes response.body, "Open admin"
    assert_not_includes response.body, "Manage users"
    assert_not_includes response.body, "Open tree"
    assert_not_includes response.body, "Current root"
  end

  test "root page shows admin content when admin root is selected" do
    admin_root = RecordingStudioAdmin::Admin.create!(name: "Admin", key: SecureRandom.hex(4))
    admin_root_recording = RecordingStudio::Recording.create!(recordable: admin_root)
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
    assert_includes response.body, "RecordingStudio API"
    assert_includes response.body, "Admin API"
    # The shared layout now surfaces root-switch choices, including other roots.
    assert_includes response.body, "Old Workspace"
    assert_not_includes response.body, "API keys"
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

  test "root switch page uses the shared host layout when admin root is current" do
    admin_root = RecordingStudioAdmin::Admin.create!(name: "Admin", key: SecureRandom.hex(4))
    admin_root_recording = RecordingStudio::Recording.create!(recordable: admin_root)
    create_access_recording(parent_recording: admin_root_recording, user: @user, role: :admin)

    get recording_studio_root_switchable.root_switch_path(
      scope: "all_roots",
      return_to: root_path
    )

    assert_response :success
    assert_includes response.body, "RecordingStudio API"
    assert_includes response.body, "Admin"
  end

  test "switching from admin to workspace returns to the host root demo" do
    admin_root = RecordingStudioAdmin::Admin.create!(name: "Admin", key: SecureRandom.hex(4))
    admin_root_recording = RecordingStudio::Recording.create!(recordable: admin_root)
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
    assert_includes response.body, "API keys"
    assert_not_includes response.body, "<h1>Admin</h1>"
  end

  test "switching from a nested root switch return target falls back to the host root demo" do
    admin_root = RecordingStudioAdmin::Admin.create!(name: "Admin", key: SecureRandom.hex(4))
    admin_root_recording = RecordingStudio::Recording.create!(recordable: admin_root)
    create_access_recording(parent_recording: admin_root_recording, user: @user, role: :admin)

    workspace = Workspace.create!(name: "Studio Workspace")
    workspace_root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    create_access_recording(parent_recording: workspace_root_recording, user: @user, role: :admin)

    nested_return_to = recording_studio_root_switchable.root_switch_path(
      scope: "all_roots",
      return_to: admin_api_path
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

  def create_access_recording(parent_recording:, user:, role:)
    with_access_creation_context do
      access = RecordingStudio::Access.create!(actor: user, role: role)
      RecordingStudio::Recording.create!(recordable: access, parent_recording: parent_recording)
    end
  end
end