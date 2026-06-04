# frozen_string_literal: true

require_relative "../../../support/api_dummy_helpers"

class ApiV1MemberActionsControllerTest < ActionDispatch::IntegrationTest
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user)
    @page_recording = create_page_recording(root_recording: @root_recording)
    @access_token = issue_oauth_access_token_for(access_recording: @access_recording, name: "Integration token")

    RecordingStudio.enable_capability(:echoable, on: "Page")
    RecordingStudioApi.register_capability_action(
      :echo,
      capability: :echoable,
      http_verb: :post,
      handler: ->(context) { context.recording }
    )
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "executes move only for folder resources when movable is enabled on Folder" do
    folder_recording = @page_recording.parent_recording

    RecordingStudio.enable_capability(:movable, on: "Folder")
    RecordingStudioApi.configuration.action_registry.instance_variable_get(:@registrations).delete("move")
    RecordingStudioApi.register_capability_action(
      :move,
      capability: :movable,
      http_verb: :post,
      handler: ->(context) { context.recording }
    )

    post "/recording_studio_api/api/v1/folders/#{folder_recording.id}/actions/move",
        headers: authorization_headers

    assert_response :success
    assert_equal folder_recording.id, JSON.parse(response.body).fetch("data").fetch("id")

    post "/recording_studio_api/api/v1/pages/#{@page_recording.id}/actions/move",
        headers: authorization_headers

    assert_response :unprocessable_entity
    assert_equal "move is not enabled for Page", JSON.parse(response.body).fetch("error")
  end

  test "dispatches a registered capability action with OAuth2 bearer authentication" do
    post "/recording_studio_api/api/v1/pages/#{@page_recording.id}/actions/echo",
         headers: authorization_headers

    assert_response :success
    assert_equal @page_recording.id, JSON.parse(response.body).fetch("data").fetch("id")
  end

  test "dispatches a registered capability action through the nested child route" do
    post "/recording_studio_api/api/v1/pages/#{@page_recording.id}/echo",
         headers: authorization_headers

    assert_response :success
    assert_equal @page_recording.id, JSON.parse(response.body).fetch("data").fetch("id")
  end

  test "dispatches the contribution version selected by the request api version" do
    RecordingStudioApi.configuration.api_versions = %w[v1 v2]
    RecordingStudioApi.configuration.version("v1") { |api| api.use :echoable, "~> 1.0" }
    RecordingStudioApi.configuration.version("v2") { |api| api.use :echoable }

    RecordingStudioApi.register_capability_action(
      :versioned_echo,
      capability: :echoable,
      version: "1.5.0",
      http_verb: :post,
      handler: ->(_context) { { version: "legacy" } },
      serializer: ->(result) { result }
    )
    RecordingStudioApi.register_capability_action(
      :versioned_echo,
      capability: :echoable,
      version: "2.0.0",
      http_verb: :post,
      handler: ->(_context) { { version: "current" } },
      serializer: ->(result) { result }
    )

    post "/recording_studio_api/api/v1/pages/#{@page_recording.id}/actions/versioned_echo",
         headers: authorization_headers

    assert_response :success
    assert_equal "legacy", JSON.parse(response.body).fetch("data").fetch("version")
  end

  test "exposes trash for trashable recordables through the nested resource route" do
    post "/recording_studio_api/api/v1/pages/#{@page_recording.id}/trash",
         headers: authorization_headers

    assert_response :success
    payload = JSON.parse(response.body).fetch("data")
    assert_equal @page_recording.id, payload.fetch("id")
    assert_not_nil RecordingStudio::Recording.unscoped.find(@page_recording.id).trashed_at
  end

  test "does not expose trash for non-trashable recordables" do
    workspace_recording = @root_recording

    post "/recording_studio_api/api/v1/workspaces/#{workspace_recording.id}/trash",
         headers: authorization_headers

    assert_response :unprocessable_entity
    assert_equal "trash is not enabled for Workspace", JSON.parse(response.body).fetch("error")
  end

  test "passes only action payload params to handlers" do
    RecordingStudioApi.register_capability_action(
      :echo_params,
      capability: :echoable,
      http_verb: :post,
      handler: ->(context) { context.params },
      serializer: ->(result) { result }
    )

    post "/recording_studio_api/api/v1/pages/#{@page_recording.id}/actions/echo_params",
         params: {
           custom_value: "safe",
           nested: { key: "value" },
           action_name: "override",
           id: "override-id",
           resource: "override-resource",
           controller: "override-controller"
         },
         headers: authorization_headers

    assert_response :success

    payload = JSON.parse(response.body).fetch("data")
    assert_equal "safe", payload.fetch("custom_value")
    assert_equal({ "key" => "value" }, payload.fetch("nested"))
    refute_includes payload.keys, "action_name"
    refute_includes payload.keys, "id"
    refute_includes payload.keys, "resource"
    refute_includes payload.keys, "controller"
    refute_includes payload.keys, "action"
    refute_includes payload.keys, "format"
  end

  test "passes authenticated access grant to capability handlers" do
    RecordingStudioApi.register_capability_action(
      :echo_access_grant,
      capability: :echoable,
      http_verb: :post,
      handler: lambda { |context|
        {
          access_recording_id: context.access_recording.id,
          access_grant_recording_id: context.access_grant.access_recording.id,
          actor_id: context.access_grant.actor.id
        }
      },
      serializer: ->(result) { result }
    )

    post "/recording_studio_api/api/v1/pages/#{@page_recording.id}/actions/echo_access_grant",
         headers: authorization_headers

    assert_response :success

    payload = JSON.parse(response.body).fetch("data")
    assert_equal @access_recording.id, payload.fetch("access_recording_id")
    assert_equal @access_recording.id, payload.fetch("access_grant_recording_id")
    assert_equal @user.id, payload.fetch("actor_id")
  end

  test "scopes capability action execution to the authenticated root recording" do
    root_recording, access_recording = create_access_recording_for(user: @user)
    in_scope_page = create_page_recording(root_recording: root_recording)
    other_root_recording, = create_access_recording_for(user: create_user(email: "other-root-actions@example.com"))
    out_of_scope_page = create_page_recording(root_recording: other_root_recording)
    scoped_token = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: access_recording,
      name: "Scoped token"
    ).value

    scoped_oauth_token = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: scoped_token.fetch(:credential).oauth_client_id,
      client_secret: scoped_token.fetch(:token)
    ).value.fetch(:access_token)

    post "/recording_studio_api/api/v1/pages/#{in_scope_page.id}/actions/echo",
        headers: { "Authorization" => "Bearer #{scoped_oauth_token}" }

    assert_response :success

    post "/recording_studio_api/api/v1/pages/#{out_of_scope_page.id}/actions/echo",
      headers: { "Authorization" => "Bearer #{scoped_oauth_token}" }

    assert_response :not_found
  end

  test "rejects a capability action for a resource outside the authenticated root scope" do
    _restricted_root_recording, restricted_access_recording = create_access_recording_for(
      user: create_user(email: "restricted-member-actions@example.com"),
      role: :edit
    )
    other_root_recording, = create_access_recording_for(user: create_user(email: "outside-member-actions@example.com"))
    hidden_page = create_page_recording(root_recording: other_root_recording)
    restricted_token = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: restricted_access_recording,
      name: "Restricted token"
    ).value

    restricted_oauth_token = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: restricted_token.fetch(:credential).oauth_client_id,
      client_secret: restricted_token.fetch(:token)
    ).value.fetch(:access_token)

    post "/recording_studio_api/api/v1/pages/#{hidden_page.id}/actions/echo",
         headers: { "Authorization" => "Bearer #{restricted_oauth_token}" }

    assert_response :not_found
    assert_equal "Resource was not found in this API scope", JSON.parse(response.body).fetch("error")
  end

  test "rejects requests without a bearer token" do
    post "/recording_studio_api/api/v1/pages/#{@page_recording.id}/actions/echo"

    assert_response :unauthorized
  end

  test "dispatches custom member actions for clients with view-only access" do
    view_user = create_user(email: "view-only-member-actions@example.com")
    view_root_recording, view_access_recording = create_access_recording_for(user: view_user, role: :view)
    view_page_recording = create_page_recording(root_recording: view_root_recording)
    view_token = issue_oauth_access_token_for(access_recording: view_access_recording, name: "View-only token")

    post "/recording_studio_api/api/v1/pages/#{view_page_recording.id}/actions/echo",
         headers: { "Authorization" => "Bearer #{view_token}" }

    assert_response :success
    assert_equal view_page_recording.id, JSON.parse(response.body).fetch("data").fetch("id")
  end

  test "trash capability owns write authorization for view-only clients" do
    view_user = create_user(email: "view-only-trash-action@example.com")
    view_root_recording, view_access_recording = create_access_recording_for(user: view_user, role: :view)
    view_page_recording = create_page_recording(root_recording: view_root_recording)
    view_token = issue_oauth_access_token_for(access_recording: view_access_recording, name: "View-only trash token")

    post "/recording_studio_api/api/v1/pages/#{view_page_recording.id}/actions/trash",
         headers: { "Authorization" => "Bearer #{view_token}" }

    assert_response :forbidden
    assert_equal "API access grant is not authorized for this capability", JSON.parse(response.body).fetch("error")
    assert_nil RecordingStudio::Recording.unscoped.find(view_page_recording.id).trashed_at
  end

  private

  def authorization_headers
    { "Authorization" => "Bearer #{@access_token}" }
  end
end
