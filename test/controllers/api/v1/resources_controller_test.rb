# frozen_string_literal: true

require_relative "../../../support/api_dummy_helpers"

class ApiV1ResourcesControllerTest < ActionDispatch::IntegrationTest
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user, role: :edit)
    @access_token = issue_oauth_access_token_for(access_recording: @access_recording, name: "Read token")
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "lists resources only within the authenticated root scope" do
    visible_page = create_page_recording(root_recording: @root_recording)
    other_root_recording, = create_access_recording_for(user: create_user(email: "other-root-resources@example.com"))
    hidden_page = create_page_recording(root_recording: other_root_recording)

    get "/recording_studio_api/api/v1/pages", headers: authorization_headers

    assert_response :success

    page_ids = JSON.parse(response.body).fetch("data").map { |row| row.fetch("id") }
    assert_includes page_ids, visible_page.id
    assert_not_includes page_ids, hidden_page.id
  end

  test "serializes recordable-specific payload for page resources" do
    page_recording = create_page_recording(root_recording: @root_recording, page_title: "Docs Landing")

    get "/recording_studio_api/api/v1/pages/#{page_recording.id}", headers: authorization_headers

    assert_response :success

    payload = JSON.parse(response.body).fetch("data")
    assert_equal page_recording.id, payload.fetch("id")
    assert_equal "page", payload.fetch("type")
    assert_equal "Docs Landing", payload.fetch("title")
    assert_equal({ "title" => "Docs Landing" }, payload.fetch("attributes"))
  end

  test "rejects a resource outside the authenticated root scope" do
    other_root_recording, = create_access_recording_for(user: create_user(email: "outside-root-resources@example.com"))
    hidden_page = create_page_recording(root_recording: other_root_recording)

    get "/recording_studio_api/api/v1/pages/#{hidden_page.id}", headers: authorization_headers

    assert_response :not_found
    assert_equal "Resource was not found in this API scope", JSON.parse(response.body).fetch("error")
  end

  private

  def authorization_headers
    { "Authorization" => "Bearer #{@access_token}" }
  end
end
