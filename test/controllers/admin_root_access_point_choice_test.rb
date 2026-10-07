# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "../test_helper"
require_relative "../dummy/config/environment"

require "devise/test/integration_helpers"
require "rails/test_help"
require "securerandom"
require_relative "../support/api_dummy_helpers"

class AdminRootAccessPointChoiceTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ApiDummyHelpers

  TEST_PASSWORD = "AccessRequestPassword!2026"

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!

    @user = User.find_or_create_by!(email: "admin-root-access-choice@example.com") do |user|
      user.password = TEST_PASSWORD
      user.password_confirmation = TEST_PASSWORD
    end

    sign_in @user

    @workspace_root_recording, = create_access_recording_for(
      user: @user,
      workspace_name: "UI Workspace",
      role: :admin
    )
  end

  def create_admin_root_recording_for(user, name:)
    admin_root = AdminRoot.create!(name: name)
    recording = RecordingStudio::Recording.create!(recordable: admin_root)
    grant_or_bootstrap_access!(recording: recording, actor: user, role: :admin)
    recording
  end

  test "workspace new form does not ask for another workspace" do
    get "/recording_studio_api/api_clients/new", params: { root_recording_id: @workspace_root_recording.id }

    assert_response :success
    assert_includes response.body, "Access point"
    assert_not_includes response.body, "Pick where this key can work."
    assert_select %(select[name="api_client[access_point_recording_id]"]), count: 1
  end

  test "admin root public new form lists manageable workspaces and creates the key there" do
    admin_recording = create_admin_root_recording_for(@user, name: "Staff admin")
    _view_only_root, = create_access_recording_for(user: @user, workspace_name: "View only studio", role: :view)
    outsider = create_user(email: "outsider-#{SecureRandom.hex(4)}@example.com")
    outsider_root, = create_access_recording_for(user: outsider, workspace_name: "Someone else's studio", role: :admin)

    get "/recording_studio_api/api_clients/new", params: { root_recording_id: admin_recording.id }

    assert_response :success
    assert_includes response.body, "Create API key"
    assert_includes response.body, "Pick where this key can work."
    assert_includes response.body, "UI Workspace"
    assert_not_includes response.body, "View only studio"
    assert_not_includes response.body, "Someone else's studio"
    assert_select %(input[type="hidden"][name="api_client[root_recording_id]"][value="#{admin_recording.id}"]), count: 1
    assert_select %(select[name="api_client[access_point_recording_id]"] option[value="#{@workspace_root_recording.id}"]), count: 1
    assert_select %(select[name="api_client[access_point_recording_id]"] option[value="#{outsider_root.id}"]), count: 0
    assert_select %(select[name="api_client[access_point_recording_id]"] option[value="#{admin_recording.id}"]), count: 0
    assert_select %(select[name="api_client[access_point_recording_id]"]), count: 1

    post "/recording_studio_api/api_clients", params: {
      api_client: {
        root_recording_id: admin_recording.id,
        access_point_recording_id: @workspace_root_recording.id,
        role: "view",
        api_client_name: "Key from admin",
        api_key: "public"
      }
    }

    assert_response :created
    client = RecordingStudioApi::ApiClient.find_by!(name: "Key from admin")
    assert_equal "public", client.api_key
    assert_equal @workspace_root_recording.id, client.access_recording.parent_recording_id
    assert_equal @workspace_root_recording.id, client.access_recording.root_recording_id

    post "/recording_studio_api/api_clients", params: {
      api_client: {
        root_recording_id: admin_recording.id,
        access_point_recording_id: outsider_root.id,
        role: "view",
        api_client_name: "Should stay blocked",
        api_key: "public"
      }
    }

    assert_response :forbidden
    assert_nil RecordingStudioApi::ApiClient.find_by(name: "Should stay blocked")
  end

  test "admin root with no manageable workspace still opens the public form" do
    lonely = create_user(email: "lonely-admin-#{SecureRandom.hex(4)}@example.com")
    admin_recording = create_admin_root_recording_for(lonely, name: "Lonely admin")
    sign_in lonely

    get "/recording_studio_api/api_clients/new", params: { root_recording_id: admin_recording.id }

    assert_response :success
    assert_includes response.body, "You need a workspace you can manage before you can create this key."
    assert_select %(select[name="api_client[access_point_recording_id]"]), count: 0
  end

  test "operations new form on a workspace stays forbidden" do
    configure_dummy_operations_api!

    get "/recording_studio_api/api_clients/new", params: {
      root_recording_id: @workspace_root_recording.id,
      api_key: "operations"
    }

    assert_response :forbidden
  end

  test "operations new form on an admin root does not ask for a workspace" do
    configure_dummy_operations_api!
    admin_recording = create_admin_root_recording_for(@user, name: "Ops admin")

    get "/recording_studio_api/api_clients/new", params: {
      root_recording_id: admin_recording.id,
      api_key: "operations"
    }

    assert_response :success
    assert_not_includes response.body, "Pick where this key can work."
    assert_includes response.body, "Access point"
    assert_select %(select[name="api_client[access_point_recording_id]"] option[value="#{admin_recording.id}"]), count: 1
    assert_select %(select[name="api_client[access_point_recording_id]"] option[value="#{@workspace_root_recording.id}"]), count: 0

    post "/recording_studio_api/api_clients", params: {
      api_client: {
        root_recording_id: admin_recording.id,
        access_point_recording_id: admin_recording.id,
        role: "view",
        api_client_name: "Ops key",
        api_key: "operations"
      }
    }

    assert_response :created
    client = RecordingStudioApi::ApiClient.find_by!(name: "Ops key")
    assert_equal "operations", client.api_key
    assert_equal admin_recording.id, client.access_recording.parent_recording_id
  end
end
