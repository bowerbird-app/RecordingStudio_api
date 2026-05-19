# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "../test_helper"
require_relative "../dummy/config/environment"

require "devise/test/integration_helpers"
require "rails/test_help"

class DocsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  TEST_PASSWORD = "DocsTestPassword!2026"

  setup do
    @user = User.find_or_create_by!(email: "docs-test@example.com") do |user|
      user.password = TEST_PASSWORD
      user.password_confirmation = TEST_PASSWORD
    end

    sign_in @user
  end

  test "install page renders successfully" do
    get docs_install_path
    assert_response :success
    assert_select "h1", text: "Install"
    assert_includes response.body, "1. Add the gem"
    assert_includes response.body, "bundle add recording_studio_api"
    assert_includes response.body, "flat_pack"
    assert_includes response.body, "generate recording_studio_api:migrations"
    assert_includes response.body, "tailwindcss:build"
  end

  test "config page renders successfully" do
    get docs_config_path
    assert_response :success
    assert_select "h1", text: "Config"
    expected_copy = "How this gem loads and merges configuration."

    assert_includes response.body, expected_copy
    assert_includes response.body, "RecordingStudioApi.configure do |config|"
    assert_includes response.body, "config.token_ttl = 45.days"
    assert_includes response.body, "config/recording_studio_api.yml"
    assert_includes response.body, "config.x.recording_studio_api"
    assert_includes response.body, "Capability action registration is documented on the API and Methods pages"
    assert_not_includes response.body, "RecordingStudioApi.register_capability_action"
  end

  test "recordable types page renders configured recordables dynamically" do
    with_recordable_types([Workspace, "Folder"]) do
      summary_data = create_recordable_type_summary_data

      get docs_recordable_types_path
      response_text = response.body.gsub(/\s+/, " ").strip

      assert_response :success
      assert_select "h1", text: "Recordable types"
      assert_includes(
        response.body,
        "The list below comes directly from RecordingStudio.configuration.recordable_types."
      )
      assert_includes response.body, "Workspace"
      assert_includes response.body, "Folder"
      assert_includes response_text, summary_data[:workspace]
      assert_includes response_text, summary_data[:folder]
    end
  end

  test "recordable types page includes dummy app defaults" do
    get docs_recordable_types_path

    assert_response :success
    assert_includes response.body, "Workspace"
    assert_includes response.body, "Folder"
    assert_includes response.body, "Page"
  end

  test "recordings tree page renders successfully" do
    workspace = Workspace.create!(name: "Tree Workspace")
    root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    folder = Folder.create!(name: "Reference")
    folder_recording = RecordingStudio::Recording.create!(recordable: folder, parent_recording: root_recording)
    page = Page.create!(title: "API")
    RecordingStudio::Recording.create!(recordable: page, parent_recording: folder_recording)
    access = RecordingStudio::Access.create!(actor: @user, role: :admin)
    RecordingStudio::Recording.create!(recordable: access, parent_recording: root_recording)

    archived_page = Page.create!(title: "Archived")
    archived_recording = RecordingStudio::Recording.create!(recordable: archived_page, parent_recording: root_recording)
    archived_recording.update_column(:trashed_at, Time.current)

    get docs_recordings_tree_path

    assert_response :success
    assert_select "h1", text: "Recordings tree"
    assert_includes response.body, "Workspace: Tree Workspace"
    assert_includes response.body, "Folder: Reference"
    assert_includes response.body, "Page: API"
    assert_includes response.body, "Access: Admin for #{@user.email}"
    assert_includes response.body, "Page: Archived"
    assert_includes response.body, "[trashed]"
    assert_includes response.body, "total in the dummy app database"
    assert_not_includes response.body, "Current structure"
    assert_not_includes response.body, "This tree is generated from RecordingStudio::Recording records"
  end

  test "gem_views page renders successfully" do
    get docs_gem_views_path
    assert_response :success
    assert_select "h1", text: "Gem Views"
    assert_includes response.body, "app/views/recording_studio_api/access_requests/new.html.erb"
    assert_includes response.body, "app/views/recording_studio_api/access_requests/create.html.erb"
    assert_includes response.body, "app/views/recording_studio_api/access_requests/index.html.erb"
    assert_includes response.body, "app/views/recording_studio_api/access_requests/show.html.erb"
  end

  test "methods page renders successfully" do
    get docs_methods_path
    assert_response :success
    assert_select "h1", text: "No methods provided by gem outside of setup"
  end

  test "api routes page renders successfully" do
    with_recordable_types_and_actions(
      ["Folder"],
      "Folder" => [action_stub(name: "move", http_verb: :post, capability: :movable, scope: :member)]
    ) do
      get docs_api_routes_path

      assert_response :success
      assert_select "h1", text: "API routes"
      assert_includes response.body, "mount RecordingStudioApi::Engine, at: &quot;/recording_studio_api&quot;"
      assert_includes response.body, "RecordingStudioApi::Engine.routes.draw do"
      assert_includes response.body, "resources :access_requests, only: %i[index show new create]"
      assert_includes response.body, "post &quot;/oauth/token&quot;, to: &quot;oauth#token&quot;"
      assert_includes response.body, "match &quot;/:resource/:id/actions/:action_name&quot;"
      assert_includes response.body, "match &quot;/:resource/:id/:action_name&quot;"
      assert_includes response.body, "via: %i[post patch put delete]"
      assert_includes response.body, "Define engine routes"
      assert_includes response.body, "Generated endpoint inventory"
      assert_includes response.body, "Action routes stay grouped under their owning resource"
      assert_includes response.body, "/recording_studio_api/api/v1/folders/:id/actions/move"
      assert_includes response.body, "Action:"
      assert_includes response.body, "movable"
    end
  end

  test "openapi endpoint renders successfully" do
    with_recordable_types([Workspace]) do
      get docs_openapi_path

      assert_response :success
      payload = JSON.parse(response.body)

      assert_equal "3.0.3", payload.fetch("openapi")
      assert_equal Rails.application.class.module_parent_name, payload.fetch("info").fetch("title")
      assert payload.fetch("paths").key?("/recording_studio_api/oauth/token")
      assert payload.fetch("paths").key?("/recording_studio_api/api/v1/workspaces")
      assert_match(
        /^resources_index_get_/,
        payload.fetch("paths").fetch("/recording_studio_api/api/v1/workspaces").fetch("get").fetch("operationId")
      )
    end
  end

  test "scalar page renders successfully" do
    get docs_scalar_path

    assert_response :success
    assert_select "h1", text: "Scalar API reference"
    assert_includes response.body, "Interactive API explorer"
    assert_includes response.body, "id=\"scalar-api-reference\""
    assert_includes response.body, docs_openapi_path
    assert_includes response.body, "@scalar/api-reference"
    assert_includes response.body, "createApiReference"
    assert_select %(a[href="#{docs_scalar_fullscreen_path}"][target="_blank"]), text: /Full screen/
  end

  test "scalar fullscreen page renders successfully" do
    get docs_scalar_fullscreen_path

    assert_response :success
    assert_includes response.body, "id=\"scalar-api-reference\""
    assert_includes response.body, "height: 100vh"
    assert_includes response.body, docs_openapi_path
    assert_includes response.body, "@scalar/api-reference"
    assert_includes response.body, "createApiReference"
  end

  test "global allow list page renders successfully" do
    get docs_global_allow_list_path

    assert_response :success
    assert_select "h1", text: "Global allow list"
    assert_includes response.body, "Global resource-type allowlist"
      assert_includes response.body, "config.recordable_types = [&quot;Workspace&quot;, &quot;Folder&quot;, &quot;Page&quot;]"
    assert_includes response.body, "def api_recordable_types"
    assert_includes response.body, "RecordingStudioApi::ApiClient"
  end

  test "add capability page renders successfully" do
    get docs_add_capability_path

    assert_response :success
    assert_select "h1", text: "Add API capability"
    assert_includes response.body, "Register a capability-backed action"
    assert_includes response.body, "RecordingStudioApi.register_capability_action"
    assert_includes response.body, "capability: :publishable"
    assert_includes response.body, "config/initializers/recording_studio_api.rb"
  end

  test "auth page renders successfully" do
    get docs_auth_path

    assert_response :success
    assert_select "h1", text: "Auth"
    assert_includes response.body, "OAuth2 client_credentials authentication"
    assert_includes response.body, "/recording_studio_api/oauth/token"
    assert_includes response.body, "grant_type=client_credentials"
    assert_includes response.body, "Authorization: Bearer &lt;access_token&gt;"
    assert_includes response.body, "RecordingStudioApi::Services::AuthenticateOauthAccessToken"
    assert_includes response.body, "Authorization after authentication"
    assert_includes response.body, "RecordingStudioApi::AccessibleRecordingScope"
    assert_includes response.body, "current_api_client"
    assert_includes response.body, "401 Unauthorized"
  end

  test "mounted recording_studio_api engine has no browser root page" do
    get "/recording_studio_api"

    assert_response :not_found
  end

  test "api docs page is not available" do
    get "/docs/api"

    assert_response :not_found
  end

  test "sidebar includes documentation links" do
    get docs_install_path

    assert_select %(a[href="#{docs_install_path}"]), text: /Install/
    assert_select %(a[href="#{docs_config_path}"]), text: /Config/
    assert_select %(a[href="#{docs_recordable_types_path}"]), text: /Recordable types/
    assert_select %(a[href="#{docs_recordings_tree_path}"]), text: /Recordings tree/
    assert_select %(a[href="#{docs_gem_views_path}"]), text: /Gem Views/
    assert_select %(a[href="#{docs_api_routes_path}"]), text: /API routes/
    assert_select %(a[href="#{docs_scalar_path}"]), text: /Scalar/
    assert_select %(a[href="#{docs_global_allow_list_path}"]), text: /Global allow list/
    assert_select %(a[href="#{docs_add_capability_path}"]), text: /Add API capability/
    assert_select %(a[href="#{docs_auth_path}"]), text: /Auth/
    assert_select %(a[href="#{docs_methods_path}"]), text: /Methods/

    methods_link_index = response.body.index(%(href="#{docs_methods_path}"))
    recordings_tree_link_index = response.body.index(%(href="#{docs_recordings_tree_path}"))

    assert_not_nil methods_link_index
    assert_not_nil recordings_tree_link_index
    assert_operator methods_link_index, :<, recordings_tree_link_index
  end

  private

  def with_recordable_types(recordable_types)
    original_recordable_types = RecordingStudio.configuration.recordable_types
    RecordingStudio.configuration.recordable_types = recordable_types
    yield
  ensure
    RecordingStudio.configuration.recordable_types = original_recordable_types
  end

  def with_recordable_types_and_actions(recordable_types, actions_by_type)
    singleton = RecordingStudioApi.singleton_class
    original_recordable_types = RecordingStudioApi.method(:api_recordable_types)
    original_actions_for = RecordingStudioApi.method(:capability_actions_for)

    singleton.send(:define_method, :api_recordable_types) { recordable_types }
    singleton.send(:define_method, :capability_actions_for) do |recordable_type|
      actions_by_type.fetch(recordable_type, [])
    end

    yield
  ensure
    singleton.send(:define_method, :api_recordable_types, original_recordable_types)
    singleton.send(:define_method, :capability_actions_for, original_actions_for)
  end

  def action_stub(name:, http_verb:, capability:, scope:)
    Struct.new(:name, :http_verb, :capability, :scope, :openapi, keyword_init: true).new(
      name: name,
      http_verb: http_verb,
      capability: capability,
      scope: scope,
      openapi: {}
    )
  end

  def create_recordable_type_summary_data
    workspace_recordings_before = RecordingStudio::Recording.where(recordable_type: "Workspace").count
    workspaces_before = Workspace.count
    folder_recordings_before = RecordingStudio::Recording.where(recordable_type: "Folder").count
    folders_before = Folder.count

    workspace = Workspace.create!(name: "Counted Workspace")
    2.times { RecordingStudio::Recording.create!(recordable: workspace) }

    folder = Folder.create!(name: "Counted Folder")
    RecordingStudio::Recording.create!(recordable: folder)

    {
      workspace: recordable_type_summary(
        workspace_recordings_before + 2,
        workspaces_before + 1,
        "recording",
        "recordable"
      ),
      folder: recordable_type_summary(
        folder_recordings_before + 1,
        folders_before + 1,
        "recording",
        "recordable"
      )
    }
  end

  def recordable_type_summary(recording_count, recordable_count, recording_word, recordable_word)
    recording_label = recording_count == 1 ? recording_word : "#{recording_word}s"
    recordable_label = recordable_count == 1 ? recordable_word : "#{recordable_word}s"

    "#{recording_count} #{recording_label} point to this type " \
      "• #{recordable_count} #{recordable_label} in the database"
  end
end
