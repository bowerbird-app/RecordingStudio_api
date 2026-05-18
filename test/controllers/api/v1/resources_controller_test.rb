# frozen_string_literal: true

require_relative "../../../support/api_dummy_helpers"

class ApiV1ResourcesControllerTest < ActionDispatch::IntegrationTest
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user, role: :edit)
    @token_payload = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: @access_recording,
      name: "Read token"
    ).value
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "lists resources outside stricter nested boundaries only" do
    visible_page = create_page_recording(root_recording: @root_recording)
    restricted_boundary = create_access_boundary_recording(
      parent_recording: @root_recording,
      minimum_role: :admin
    )
    hidden_page = create_page_recording(root_recording: @root_recording, parent_recording: restricted_boundary)

    get "/recording_studio_api/api/v1/pages", headers: authorization_headers

    assert_response :success

    page_ids = JSON.parse(response.body).fetch("data").map { |row| row.fetch("id") }
    assert_includes page_ids, visible_page.id
    assert_not_includes page_ids, hidden_page.id
  end

  test "rejects a resource behind a stricter nested boundary" do
    restricted_boundary = create_access_boundary_recording(
      parent_recording: @root_recording,
      minimum_role: :admin
    )
    hidden_page = create_page_recording(root_recording: @root_recording, parent_recording: restricted_boundary)

    get "/recording_studio_api/api/v1/pages/#{hidden_page.id}", headers: authorization_headers

    assert_response :not_found
    assert_equal "Resource was not found in this API scope", JSON.parse(response.body).fetch("error")
  end

  private

  def authorization_headers
    { "Authorization" => "Bearer #{@token_payload.fetch(:token)}" }
  end
end
