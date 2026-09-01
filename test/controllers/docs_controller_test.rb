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
    RecordingStudioApi.configuration.documentation_enabled = true
    RecordingStudioApi.configuration.documentation_access = :public
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
    assert_includes response.body, "Wire API access"
    assert_includes response.body, "RecordingStudioApi::Services::ProvisionApiClient"
    assert_includes response.body, "context.access_grant.authorize!"
  end

  test "config page renders successfully" do
    get docs_config_path
    assert_response :success
    assert_select "h1", text: "Config"
    expected_copy = "How this gem loads and merges configuration."

    assert_includes response.body, expected_copy
    assert_includes response.body, "RecordingStudioApi.configure do |config|"
    assert_includes response.body, "config.credential_ttl = 45.days"
    assert_includes response.body, "config.access_token_ttl = 1.hour"
    assert_includes response.body, "config.api_versions = %w[v1 v2]"
    assert_includes response.body, "config.default_api_version = &quot;v2&quot;"
    assert_includes response.body, "config.rate_limit_oauth_enabled = Rails.env.production?"
    assert_includes response.body, "config.rate_limit_api_pre_auth_enabled = Rails.env.production?"
    assert_includes response.body, "config.rate_limit_api_enabled = true"
    assert_includes response.body, "config.rate_limit_oauth_requests = 10"
    assert_includes response.body, "config.rate_limit_api_pre_auth_requests = 120"
    assert_includes response.body, "config.rate_limit_api_read_requests = 300"
    assert_includes response.body, "config.rate_limit_api_write_requests = 60"
    assert_includes response.body, "config.rate_limit_fail_closed = Rails.env.production?"
    assert_includes response.body, "config.rate_limit_fail_closed_buckets = %w[oauth api_pre_auth api]"
    assert_includes response.body, "config.api_request_logging_enabled = true"
    assert_includes response.body, "config.api_request_logging_payload_mode ="
    assert_includes response.body, "metadata_only"
    assert_includes response.body, "config.version"
    assert_includes response.body, "api.use"
    assert_includes response.body, "Gem::Requirement"
    assert_includes response.body, "Gem::Version"
    assert_not_includes response.body, "RecordingStudioApi.register_capability_action"
  end

  test "recordable types page renders configured recordables dynamically" do
    with_recordable_types([Workspace, "Folder"]) do
      create_recordable_type_summary_data

      get docs_recordable_types_path
      response_text = response.body.gsub(/\s+/, " ").strip

      assert_response :success
      assert_select "h1", text: "Recordable types"
      assert_includes response.body, "Distinct recordable types currently present in RecordingStudio::Recording."
      assert_includes response.body, "Type"
      assert_includes response.body, "Recordings"
      assert_includes response.body, "Recordables"
      assert_includes response.body, "Workspace"
      assert_includes response.body, "Folder"
      assert_includes response_text, pluralized_label(RecordingStudio::Recording.where(recordable_type: "Workspace").count, "recording")
      assert_includes response_text, pluralized_label(Workspace.count, "recordable")
      assert_includes response_text, pluralized_label(RecordingStudio::Recording.where(recordable_type: "Folder").count, "recording")
      assert_includes response_text, pluralized_label(Folder.count, "recordable")
    end
  end

  test "recordable types page includes dummy app defaults" do
    workspace = Workspace.create!(name: "Default Workspace")
    workspace_recording = RecordingStudio::Recording.create!(recordable: workspace)
    folder = Folder.create!(name: "Default Folder")
    folder_recording = RecordingStudio::Recording.create!(recordable: folder, parent_recording: workspace_recording)
    page = Page.create!(title: "Default Page")
    RecordingStudio::Recording.create!(recordable: page, parent_recording: folder_recording)

    get docs_recordable_types_path

    assert_response :success
    assert_includes response.body, "Distinct recordable types currently present in RecordingStudio::Recording."
    assert_includes response.body, "Workspace"
    assert_includes response.body, "Folder"
    assert_includes response.body, "Page"
  end

  test "api hierarchy page renders successfully" do
    get docs_api_hierarchy_path

    assert_response :success
    assert_select "h1", text: "API hierarchy"
    assert_includes response.body, "How API recordables nest beneath each other in the Recording Studio tree."
    assert_includes response.body, "RecordingStudioApi::AccessGrant"
    assert_includes response.body, "runtime context"
    assert_includes response.body, "authenticated API client"
    assert_includes response.body, "Folder"
    assert_includes response.body, "Access"
  end

  test "recordings tree page renders successfully" do
    workspace = Workspace.create!(name: "Tree Workspace")
    root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    folder = Folder.create!(name: "Reference")
    folder_recording = RecordingStudio::Recording.create!(recordable: folder, parent_recording: root_recording)
    page = Page.create!(title: "API")
    RecordingStudio::Recording.create!(recordable: page, parent_recording: folder_recording)
    RecordingStudioAccessible::AccessCreationContext.allow do
      access = RecordingStudio::Access.create!(actor: @user, role: :admin)
      RecordingStudio::Recording.create!(recordable: access, parent_recording: root_recording)
    end

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
    assert_select "h1", text: "Methods"
    assert_includes response.body, "Reference for the public Ruby entrypoints and runtime context used by API handlers."
    assert_includes response.body, "RecordingStudioApi.register_capability_action"
    assert_includes response.body, "context.access_grant.authorize!"
  end

  test "versions page renders successfully" do
    get docs_versions_path

    assert_response :success
    assert_select "h1", text: "Versions"
    assert_includes response.body, "contribution contract versions"
    assert_includes response.body, "config.api_versions"
    assert_includes response.body, "config.default_api_version"
    assert_includes response.body, "config.version"
    assert_includes response.body, "api.use"
    assert_includes response.body, "1.23"
    assert_includes response.body, "version_notes"
    assert_includes response.body, "deprecation"
    assert_includes response.body, "removal_date"
    assert_includes response.body, "not gem package versions"
    assert_includes response.body, "Resolution and Validation"
    assert_includes response.body, "Gem::Version"
    assert_includes response.body, "Gem::Requirement"
    assert_includes response.body, "RecordingStudioApi::ConfigurationError"
    assert_includes response.body, "duplicate contribution version"
    assert_includes response.body, "omitted for that public API version"
    assert_includes response.body, "/APIdocs/v1"
    assert_includes response.body, "/APIdocs/v2"
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
      assert_includes response.body, "recording_studio_admin_for :api, at: &quot;/api&quot;"
      assert_includes response.body, "RecordingStudioApi::Engine.routes.draw do"
      assert_includes response.body, "get &quot;/admin_api&quot;, to: &quot;admin_dashboards#show&quot;"
      assert_includes response.body, "get &quot;/admin_api/logs&quot;, to: &quot;admin_logs#index&quot;"
      assert_includes response.body, "GET /api/screens/api_keys"
      assert_includes response.body, "resources :api_clients, controller: &quot;access_requests&quot;, only: %i[index show new create edit update]"
      assert_includes response.body, "post &quot;/oauth/token&quot;, to: &quot;oauth#token&quot;"
      assert_includes response.body, "namespace :v1 do"
      assert_includes response.body, "RecordingStudioApi.api_versions - ["
      assert_includes response.body, "namespace api_version.to_sym do"
      assert_includes response.body, "to: &quot;/recording_studio_api/api/v1/resources#index&quot;"
      assert_includes response.body, "to: &quot;resources#index&quot;"
      assert_includes response.body, "match &quot;/:resource/:id/actions/:action_name&quot;"
      assert_includes response.body, "match &quot;/:resource/:id/:action_name&quot;"
      assert_includes response.body, "via: %i[post patch put delete]"
      assert_includes response.body, "Define engine routes"
      assert_includes response.body, "Generated endpoint inventory"
      assert_includes response.body, "Action routes stay grouped under their owning resource"
      assert_includes response.body, "Admin browser routes are separate from JSON API routes"
      assert_includes response.body, "/recording_studio_api/api/v1/folders/:id/actions/move"
      assert_includes response.body, "config.version"
      assert_includes response.body, "shared controller implementation"
      assert_includes response.body, "Action:"
      assert_includes response.body, "move"
    end
  end

  test "auth page renders successfully" do
    get docs_auth_path

    assert_response :success
    assert_select "h1", text: "Auth"
    assert_includes response.body, "How OAuth2 credentials and delegated app connects become a RecordingStudioApi access grant for endpoint dispatch."
    assert_includes response.body, "grant_type=client_credentials"
    assert_includes response.body, "http://localhost:3000/recording_studio_api/api/v2/workspaces"
    assert_includes response.body, "/api/&lt;version&gt;"
    assert_includes response.body, "newest compatible capability contract"
    assert_includes response.body, "Authorization: Bearer &lt;access_token&gt;"
    assert_includes response.body, "RecordingStudioApi::Services::IssueOauthAccessToken"
    assert_includes response.body, "RecordingStudioApi::Services::AuthenticateOauthAccessToken"
    assert_includes response.body, "RecordingStudioApi::AccessGrant"
    assert_includes response.body, "current_access_grant"
    assert_includes response.body, "current_api_client"
    assert_includes response.body, "401 Unauthorized"
    assert_includes response.body, "429 Too Many Requests"
  end

  test "openapi endpoint renders successfully" do
    with_recordable_types([Workspace, "RecordingStudio::Access"]) do
      get docs_openapi_path(version: "v1")

      assert_response :success
      payload = JSON.parse(response.body)

      assert_equal "3.0.3", payload.fetch("openapi")
      assert_equal RecordingStudioApi.openapi_title, payload.fetch("info").fetch("title")
      assert payload.fetch("paths").key?("/recording_studio_api/oauth/token")
      assert payload.fetch("paths").key?("/recording_studio_api/api/v1/workspaces")
      assert payload.fetch("paths").fetch("/recording_studio_api/api/v1/workspaces").key?("post")
      assert payload.fetch("paths").fetch("/recording_studio_api/api/v1/workspaces/{id}").key?("patch")
      assert payload.fetch("paths").fetch("/recording_studio_api/api/v1/workspaces/{id}").key?("delete")
      assert_match(
        /^resources_index_get_/,
        payload.fetch("paths").fetch("/recording_studio_api/api/v1/workspaces").fetch("get").fetch("operationId")
      )
    end
  end

  test "openapi endpoint supports explicit version" do
    with_recordable_types([Workspace, "RecordingStudio::Access"]) do
      RecordingStudioApi.configuration.api_versions = %w[v1 v2]

      get docs_openapi_path(version: "v2")

      assert_response :success
      payload = JSON.parse(response.body)

      assert payload.fetch("paths").key?("/recording_studio_api/api/v2/workspaces")
      refute payload.fetch("paths").key?("/recording_studio_api/api/v1/workspaces")
    ensure
      RecordingStudioApi.configuration.api_versions = ["v1"]
      RecordingStudioApi.configuration.default_api_version = "v1"
    end
  end

  test "scalar page renders successfully" do
    get public_api_scalar_docs_version_path(version: "v1")

    assert_response :success
    assert_select "h1", text: "Recording Studio API"
    assert_includes response.body, "Interactive API explorer"
    assert_not_includes response.body, "Test auth helper"
    assert_select %(form[action="#{public_api_scalar_test_credential_path(version: 'v1')}"]), count: 0
    assert_includes response.body, "id=\"scalar-api-reference\""
    assert_includes response.body, public_api_scalar_docs_openapi_path(version: "v1")
    assert_select "#scalar-api-reference-source[src^='/assets/recording_studio_api/scalar-1.64.0']", count: 1
    assert_select "#scalar-api-reference-source[src^='http']", count: 0
    assert_includes response.body, "createApiReference"
    assert_includes response.body, 'source.addEventListener("load", initializeScalar'
    assert_select %(body[data-recording-studio-default-layout="true"]), count: 1
    assert_select %(a[href="#{public_api_scalar_docs_fullscreen_path(version: 'v1')}"]), text: "Full width"
    assert_includes response.headers.fetch("Vary"), "Cookie"
  end

  test "APIdocs routes render versioned scalar and openapi endpoints" do
    create_manageable_workspace_root(name: "Scalar APIdocs Workspace")
    RecordingStudioApi.configuration.api_versions = %w[v1 v2]

    get api_docs_path(version: "v2")

    assert_response :success
    assert_includes response.body, "for V2"
    assert_includes response.body, api_docs_openapi_path(version: "v2")
    assert_select %(a[href="#{api_docs_fullscreen_path(version: 'v2')}"]), text: "Full width"

    get api_docs_openapi_path(version: "v2")

    assert_response :success
    payload = JSON.parse(response.body)
    assert payload.fetch("paths").key?("/recording_studio_api/api/v2/workspaces")
  ensure
    RecordingStudioApi.configuration.api_versions = ["v1"]
    RecordingStudioApi.configuration.default_api_version = "v1"
  end

  test "scalar test auth uses the requested assignable role for the selected access point" do
    root_recording = create_manageable_workspace_root(name: "Scalar Workspace")

    post public_api_scalar_test_credential_path(version: "v1"), params: {
      access_point_recording_id: root_recording.id,
      role: "edit"
    }

    assert_redirected_to public_api_scalar_test_credential_path(version: "v1")

    follow_redirect!

    assert_response :success
    assert_select %(body[data-recording-studio-default-layout="true"]), count: 1
    assert_select "h1", text: "API test token"
    assert_select %(a[href="#{public_api_scalar_docs_version_path(version: 'v1')}"]), minimum: 1
    assert_includes response.body, "API test bearer token issued."
    assert_includes response.body, "Bearer rsapi_at_"
    assert_includes response.body, "Admin"
    assert_select %(select[name="access_point_recording_id"]), count: 1
    assert_select %(select[name="role"] option[value="edit"][selected="selected"]), count: 1
    assert_select %(button[type="submit"]), text: "Generate token", count: 1
    assert_includes response.body, "Workspace: Scalar Workspace"
    assert_includes response.body, "Scoped sample IDs"
    assert_select %(form[action="#{public_api_scalar_test_credential_path(version: 'v1')}"] input[name="_method"][value="delete"]), count: 1
  end

  test "scalar test auth revokes the session bearer token" do
    root_recording = create_manageable_workspace_root(name: "Scalar Revoke Workspace")

    post public_api_scalar_test_credential_path(version: "v1"), params: {
      access_point_recording_id: root_recording.id,
      role: "admin"
    }
    token = RecordingStudioApi::ApiAccessToken.order(created_at: :desc).first

    delete public_api_scalar_test_credential_path(version: "v1")

    assert_redirected_to public_api_scalar_test_credential_path(version: "v1")
    assert_not_nil token.reload.revoked_at

    follow_redirect!

    assert_response :success
    assert_includes response.body, "API test bearer token revoked."
    assert_not_includes response.body, "Bearer rsapi_at_"
  end

  test "standalone test token page requires authentication" do
    sign_out @user

    get public_api_scalar_test_credential_path(version: "v1")
    assert_response :unauthorized

    post public_api_scalar_test_credential_path(version: "v1")
    assert_response :unauthorized

    delete public_api_scalar_test_credential_path(version: "v1")
    assert_response :unauthorized
  end

  test "standalone test token page requires manageable API access" do
    get public_api_scalar_test_credential_path(version: "v1")
    assert_response :forbidden

    post public_api_scalar_test_credential_path(version: "v1")
    assert_response :forbidden
  end

  test "standalone test token page is hidden when disabled" do
    Rails.env.stub(:local?, false) do
      get public_api_scalar_test_credential_path(version: "v1")
      assert_response :not_found

      post public_api_scalar_test_credential_path(version: "v1")
      assert_response :not_found

      delete public_api_scalar_test_credential_path(version: "v1")
      assert_response :not_found
    end
  end

  test "scalar test auth reuses the same access recording for repeated issues" do
    root_recording = create_manageable_workspace_root(name: "Scalar Reissue Workspace")

    post public_api_scalar_test_credential_path(version: "v1"), params: {
      access_point_recording_id: root_recording.id,
      role: "admin"
    }

    first_credential = RecordingStudioApi::ApiCredential.order(created_at: :desc).first

    post public_api_scalar_test_credential_path(version: "v1"), params: {
      access_point_recording_id: root_recording.id,
      role: "admin"
    }

    direct_access_recordings = RecordingStudioAccessible.access_recordings_for_actor(recording: root_recording, actor: @user)

    assert_not_nil first_credential.reload.revoked_at
    assert_equal 1, direct_access_recordings.length
  end

  test "scalar fullscreen page renders successfully" do
    get public_api_scalar_docs_fullscreen_path(version: "v1")

    assert_response :success
    assert_includes response.body, "id=\"scalar-api-reference\""
    assert_includes response.body, "height: 100vh"
    assert_includes response.body, public_api_scalar_docs_openapi_path(version: "v1")
    assert_select "#scalar-api-reference-source[src^='/assets/recording_studio_api/scalar-1.64.0']", count: 1
    assert_select "#scalar-api-reference-source[src^='http']", count: 0
    assert_includes response.body, "createApiReference"
    assert_includes response.body, 'source.addEventListener("load", initializeScalar'
    assert_select %(body[data-recording-studio-default-layout]), count: 0
  end

  test "anonymous public scalar documentation uses the standalone layout" do
    sign_out @user

    get public_api_scalar_docs_version_path(version: "v1")

    assert_response :success
    assert_select %(body[data-recording-studio-default-layout]), count: 0
    assert_includes response.body, "height: 100vh"
    assert_includes response.body, public_api_scalar_docs_openapi_path(version: "v1")
    assert_includes response.headers.fetch("Vary"), "Cookie"

    get public_api_scalar_docs_fullscreen_path(version: "v1")
    assert_response :success

    get public_api_scalar_docs_openapi_path(version: "v1")
    assert_response :success
  end

  test "private scalar documentation requires authentication for every endpoint" do
    RecordingStudioApi.configuration.documentation_access = :authenticated
    sign_out @user

    get public_api_scalar_docs_version_path(version: "v1")
    assert_response :unauthorized

    get public_api_scalar_docs_fullscreen_path(version: "v1")
    assert_response :unauthorized

    get public_api_scalar_docs_openapi_path(version: "v1")
    assert_response :unauthorized
  ensure
    RecordingStudioApi.configuration.documentation_access = :public
  end

  test "disabled scalar documentation is not routably exposed" do
    RecordingStudioApi.configuration.documentation_enabled = false

    get public_api_scalar_docs_version_path(version: "v1")

    assert_response :not_found
  ensure
    RecordingStudioApi.configuration.documentation_enabled = true
  end

  test "add capability page renders successfully" do
    get docs_add_capability_path

    assert_response :success
    assert_select "h1", text: "Add API capability"
    assert_includes response.body, "Register a capability-backed action"
    assert_includes response.body, "RecordingStudioApi.register_capability_action"
    assert_includes response.body, "capability: :publishable"
    assert_includes response.body, "config/initializers/recording_studio_api.rb"
    assert_includes response.body, "context.access_grant.authorize!"
    assert_includes response.body, "Authorization contract"
  end

  test "mounted recording_studio_api engine has no browser root page" do
    get "/recording_studio_api"

    assert_response :not_found
  end

  test "api docs page is not available" do
    get "/docs/api"

    assert_response :not_found
  end

  test "global allow list page is not available" do
    get "/docs/global_allow_list"

    assert_response :not_found
  end

  test "docs pages include documentation links" do
    get docs_install_path

    assert_select %(a[href="#{docs_install_path}"]), text: /Install/
    assert_select %(a[href="#{docs_config_path}"]), text: /Config/
    assert_select %(a[href="#{docs_recordable_types_path}"]), text: /Recordable types/
    assert_select %(a[href="#{docs_recordings_tree_path}"]), text: /Recordings tree/
    assert_select %(a[href="#{docs_gem_views_path}"]), text: /Gem Views/
    assert_select %(a[href="#{docs_api_routes_path}"]), text: /API routes/
    assert_select %(a[href="#{public_api_scalar_docs_path}"]), text: /Scalar/
    assert_select %(a[href="#{docs_add_capability_path}"]), text: /Add API capability/
    assert_select %(a[href="#{docs_auth_path}"]), text: /Auth/
    assert_select %(a[href="#{docs_methods_path}"]), text: /Methods/
    assert_select %(a[href="#{docs_versions_path}"]), text: /Versions/
    assert_select %(a[href="#{docs_api_hierarchy_path}"]), text: /API hierarchy/
    assert_select %(a[href="/docs/global_allow_list"]), false

    methods_link_index = response.body.index(%(href="#{docs_methods_path}"))
    versions_link_index = response.body.index(%(href="#{docs_versions_path}"))
    api_hierarchy_link_index = response.body.index(%(href="#{docs_api_hierarchy_path}"))
    recordings_tree_link_index = response.body.index(%(href="#{docs_recordings_tree_path}"))

    assert_not_nil methods_link_index
    assert_not_nil versions_link_index
    assert_not_nil api_hierarchy_link_index
    assert_not_nil recordings_tree_link_index
    assert_operator methods_link_index, :<, recordings_tree_link_index
    assert_operator methods_link_index, :<, versions_link_index
    assert_operator versions_link_index, :<, recordings_tree_link_index
    assert_operator methods_link_index, :<, api_hierarchy_link_index
    assert_operator api_hierarchy_link_index, :<, recordings_tree_link_index
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
    singleton.send(:define_method, :capability_actions_for) do |recordable_type, **|
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

    2.times do |index|
      workspace = Workspace.create!(name: "Counted Workspace #{index}")
      RecordingStudio::Recording.create!(recordable: workspace)
    end

    folder = Folder.create!(name: "Counted Folder")
    RecordingStudio::Recording.create!(recordable: folder)

    {
      workspace: recordable_type_summary(
        workspace_recordings_before + 2,
        workspaces_before + 2,
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

  def create_manageable_workspace_root(name:)
    workspace = Workspace.create!(name: name)
    root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    RecordingStudioAccessible::AccessCreationContext.allow do
      access = RecordingStudio::Access.create!(actor: @user, role: :admin)
      RecordingStudio::Recording.create!(recordable: access, parent_recording: root_recording)
    end

    root_recording
  end

  def recordable_type_summary(recording_count, recordable_count, recording_word, recordable_word)
    recording_label = recording_count == 1 ? recording_word : "#{recording_word}s"
    recordable_label = recordable_count == 1 ? recordable_word : "#{recordable_word}s"

    "#{recording_count} #{recording_label} point to this type " \
      "• #{recordable_count} #{recordable_label} in the database"
  end

  def pluralized_label(count, word)
    suffix = count == 1 ? word : "#{word}s"
    "#{count} #{suffix}"
  end
end
