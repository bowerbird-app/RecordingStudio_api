# frozen_string_literal: true

require_relative "../../../support/api_dummy_helpers"

class ApiV1ResourcePaginationTest < ActionDispatch::IntegrationTest
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user, role: :edit)
    @access_token = issue_oauth_access_token_for(access_recording: @access_recording, name: "Pagination token")
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "pages a descending created_at collection with the next token" do
    older = create_page_recording(root_recording: @root_recording, page_title: "Older page")
    middle = create_page_recording(root_recording: @root_recording, page_title: "Middle page")
    newer = create_page_recording(root_recording: @root_recording, page_title: "Newer page")
    older.update_columns(created_at: 3.days.ago, updated_at: Time.current)
    middle.update_columns(created_at: 2.days.ago, updated_at: Time.current)
    newer.update_columns(created_at: 1.day.ago, updated_at: Time.current)

    ids = page_ids("/recording_studio_api/api/v1/pages", limit: 1, sort: "created_at", order: "desc")

    assert_equal [newer.id, middle.id, older.id], ids
  end

  test "clamps the page size and falls back when configured limits are not positive" do
    get "/recording_studio_api/api/v1/pages", params: { limit: 500 }, headers: authorization_headers

    assert_response :success
    assert_equal 100, JSON.parse(response.body).dig("meta", "limit")

    RecordingStudioApi.configuration.pagination_default_limit = 0
    RecordingStudioApi.configuration.pagination_max_limit = 0

    get "/recording_studio_api/api/v1/pages", headers: authorization_headers
    assert_response :success
    assert_equal 50, JSON.parse(response.body).dig("meta", "limit")

    get "/recording_studio_api/api/v1/pages", params: { limit: 150 }, headers: authorization_headers
    assert_response :success
    assert_equal 100, JSON.parse(response.body).dig("meta", "limit")
  end

  test "rejects an order that is not asc or desc" do
    get "/recording_studio_api/api/v1/pages", params: { order: "sideways" }, headers: authorization_headers

    assert_response :unprocessable_entity
    assert_equal "invalid_pagination_token", JSON.parse(response.body).dig("error", "code")
    assert_equal "order must be asc or desc", JSON.parse(response.body).dig("error", "message")
  end

  test "rejects a pagination token that does not match the request" do
    create_page_recording(root_recording: @root_recording, page_title: "Token page one")
    create_page_recording(root_recording: @root_recording, page_title: "Token page two")
    RecordingStudio::Recording.create!(
      recordable: Folder.create!(name: "Token folder"),
      parent_recording: @root_recording
    )
    RecordingStudio::Recording.create!(
      recordable: Folder.create!(name: "Another token folder"),
      parent_recording: @root_recording
    )

    token = next_token("/recording_studio_api/api/v1/pages", limit: 1, sort: "created_at", order: "asc")

    get "/recording_studio_api/api/v1/pages",
        params: { limit: 1, sort: "created_at", order: "desc", pagination_token: token },
        headers: authorization_headers
    assert_response :unprocessable_entity
    assert_equal "Pagination token does not match requested order", JSON.parse(response.body).dig("error", "message")

    get "/recording_studio_api/api/v1/folders",
        params: { limit: 1, sort: "created_at", order: "asc", pagination_token: token },
        headers: authorization_headers
    assert_response :unprocessable_entity
    assert_equal "Pagination token does not match requested resource", JSON.parse(response.body).dig("error", "message")

    name_token = next_token("/recording_studio_api/api/v1/folders", limit: 1, sort: "name", order: "asc")
    get "/recording_studio_api/api/v1/folders",
        params: { limit: 1, sort: "created_at", order: "asc", pagination_token: name_token },
        headers: authorization_headers
    assert_response :unprocessable_entity
    assert_equal "Pagination token does not match requested sort", JSON.parse(response.body).dig("error", "message")
  end

  test "rejects a pagination token issued for another named API" do
    create_page_recording(root_recording: @root_recording, page_title: "Public page one")
    create_page_recording(root_recording: @root_recording, page_title: "Public page two")
    token = next_token("/recording_studio_api/api/v1/pages", limit: 1, sort: "created_at", order: "asc")

    RecordingStudioApi.configuration.api(:operations) { |api| api.default_access = :read_only }
    RecordingStudioApi.register_default_resource_actions!(api: :operations)
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      api: :operations,
      serializer: ->(recordable, **) { { name: recordable.name } },
      output_keys: %i[name],
      operations: %i[index show]
    )
    RecordingStudioApi.register_recordable_type_api(
      "Page",
      api: :operations,
      serializer: ->(page, **) { { title: page.title } },
      output_keys: %i[title],
      operations: %i[index show]
    )
    operations_token = issue_operations_token

    get "/recording_studio_api/apis/operations/v1/pages",
        params: { limit: 1, pagination_token: token },
        headers: { "Authorization" => "Bearer #{operations_token}" }

    assert_response :unprocessable_entity
    assert_equal "Pagination token does not match requested API", JSON.parse(response.body).dig("error", "message")
  end

  private

  def authorization_headers
    { "Authorization" => "Bearer #{@access_token}" }
  end

  def next_token(path, **params)
    get path, params: params, headers: authorization_headers
    assert_response :success
    token = JSON.parse(response.body).dig("meta", "next_pagination_token")
    assert token.present?
    token
  end

  def page_ids(path, **params)
    ids = []
    token = nil

    loop do
      request_params = params.merge(pagination_token: token).compact
      get path, params: request_params, headers: authorization_headers
      assert_response :success, response.body
      payload = JSON.parse(response.body)
      ids.concat(payload.fetch("records").map { |row| row.fetch("id") })
      token = payload.dig("meta", "next_pagination_token")
      break if token.blank?
    end

    ids
  end

  def issue_operations_token
    provision_result = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_point_recording: access_point_recording_for(@access_recording),
      manager_actor: access_manager_for(@access_recording),
      role: @access_recording.recordable.role,
      name: "Operations pagination client",
      api: :operations
    )
    raise provision_result.error unless provision_result.success?

    payload = provision_result.value
    token_result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: payload.fetch(:credential).oauth_client_id,
      client_secret: payload.fetch(:token),
      api: :operations
    )
    raise token_result.error unless token_result.success?

    token_result.value.fetch(:access_token)
  end
end
