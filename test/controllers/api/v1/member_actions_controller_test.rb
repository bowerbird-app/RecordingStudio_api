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
    @token_payload = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: @access_recording,
      name: "Integration token"
    ).value

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

  test "dispatches a registered capability action with bearer authentication" do
    post "/recording_studio_api/api/v1/pages/#{@page_recording.id}/actions/echo",
         headers: authorization_headers

    assert_response :success
    assert_equal @page_recording.id, JSON.parse(response.body).fetch("data").fetch("id")
  end

  test "scopes token access to the parent boundary subtree instead of the whole root" do
    root_recording, boundary_recording, access_recording = create_access_recording_under_boundary_for(user: @user)
    in_scope_page = create_page_recording(root_recording: root_recording, parent_recording: boundary_recording)
    out_of_scope_page = create_page_recording(root_recording: root_recording)
    scoped_token = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: access_recording,
      name: "Boundary token"
    ).value.fetch(:token)

    get "/recording_studio_api/api/v1/pages/#{in_scope_page.id}/actions",
        headers: { "Authorization" => "Bearer #{scoped_token}" }

    assert_response :success

    get "/recording_studio_api/api/v1/pages/#{out_of_scope_page.id}/actions",
        headers: { "Authorization" => "Bearer #{scoped_token}" }

    assert_response :not_found
  end

  test "rejects requests without a bearer token" do
    post "/recording_studio_api/api/v1/pages/#{@page_recording.id}/actions/echo"

    assert_response :unauthorized
  end

  private

  def authorization_headers
    { "Authorization" => "Bearer #{@token_payload.fetch(:token)}" }
  end
end
