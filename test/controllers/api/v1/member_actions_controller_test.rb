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

  test "lists only capability actions enabled for the target recordable type" do
    get "/recording_studio_api/api/v1/pages/#{@page_recording.id}/actions",
        headers: authorization_headers

    assert_response :success
    assert_equal ["echo"], JSON.parse(response.body).fetch("data").map { |row| row.fetch("name") }
  end

  test "exposes move only for folder resources when movable is enabled on Folder" do
    folder_recording = @page_recording.parent_recording

    RecordingStudio.enable_capability(:movable, on: "Folder")
    RecordingStudioApi.register_capability_action(
      :move,
      capability: :movable,
      http_verb: :post,
      handler: RecordingStudioApi::Services::MoveRecording
    )

    get "/recording_studio_api/api/v1/folders/#{folder_recording.id}/actions",
        headers: authorization_headers

    assert_response :success
    folder_actions = JSON.parse(response.body).fetch("data").map { |row| row.fetch("name") }
    assert_includes folder_actions, "move"

    get "/recording_studio_api/api/v1/pages/#{@page_recording.id}/actions",
        headers: authorization_headers

    assert_response :success
    page_actions = JSON.parse(response.body).fetch("data").map { |row| row.fetch("name") }
    assert_not_includes page_actions, "move"
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

  test "scopes token access to the authenticated root recording" do
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

    get "/recording_studio_api/api/v1/pages/#{in_scope_page.id}/actions",
        headers: { "Authorization" => "Bearer #{scoped_oauth_token}" }

    assert_response :success

    get "/recording_studio_api/api/v1/pages/#{out_of_scope_page.id}/actions",
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

  private

  def authorization_headers
    { "Authorization" => "Bearer #{@access_token}" }
  end
end
