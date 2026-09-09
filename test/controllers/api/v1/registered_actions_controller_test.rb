# frozen_string_literal: true

require_relative "../../../support/api_dummy_helpers"

class ApiV1RegisteredActionsControllerTest < ActionDispatch::IntegrationTest
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user)
    @page_recording = create_page_recording(root_recording: @root_recording)
    @access_token = issue_oauth_access_token_for(access_recording: @access_recording, name: "Registered action token")
    RecordingStudioApi.register_recordable_type_api(
      "Page",
      operations: %i[index show],
      serializer: ->(recordable, **) { { title: recordable.title } },
      output_keys: %i[title]
    )
    RecordingStudioApi.register_action(
      :ping,
      http_verb: :get,
      path: "ping",
      handler: lambda { |context|
        {
          ok: true,
          has_recording: context.respond_to?(:recording),
          access_recording_id: context.access_recording&.id
        }
      }
    )
    RecordingStudioApi.register_action(
      :echo,
      http_verb: :post,
      path: "echo/:key",
      handler: lambda { |context|
        { key: context.params[:key], message: context.params[:message], api_key: context.api_key }
      }
    )
    RecordingStudioApi.register_action(
      :shout,
      http_verb: :post,
      path: "shout",
      serializer: ->(result) { { wrapped: result } },
      input_contract: {
        reject_unknown: true,
        fields: {
          message: { type: :string, required: true, allow_blank: false }
        }
      },
      handler: ->(context) { { message: context.params[:message] } }
    )
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "dispatches a registered get action with no recordable" do
    get "/recording_studio_api/api/v1/ping", headers: authorization_headers

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal true, payload.fetch("ok")
    assert_equal false, payload.fetch("has_recording")
    assert_not_nil payload.fetch("access_recording_id")
    assert_not_equal @page_recording.id, payload.fetch("access_recording_id")
  end

  test "dispatches a registered post action with path params" do
    post "/recording_studio_api/api/v1/echo/widget",
         params: { message: "hello" },
         as: :json,
         headers: authorization_headers

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "widget", payload.fetch("key")
    assert_equal "hello", payload.fetch("message")
    assert_equal "public", payload.fetch("api_key")
  end

  test "serializes a registered action and rejects invalid input" do
    post "/recording_studio_api/api/v1/shout",
         params: { message: "hi" },
         as: :json,
         headers: authorization_headers

    assert_response :success
    assert_equal({ "wrapped" => { "message" => "hi" } }, JSON.parse(response.body))

    post "/recording_studio_api/api/v1/shout",
         params: {},
         as: :json,
         headers: authorization_headers

    assert_response :unprocessable_entity
    assert_equal "invalid_input", JSON.parse(response.body).dig("error", "code")
  end

  test "rejects unauthenticated registered actions" do
    get "/recording_studio_api/api/v1/ping"

    assert_response :unauthorized
    assert_equal "authentication_failed", JSON.parse(response.body).dig("error", "code")
  end

  test "rejects a public token on an operations-only action" do
    RecordingStudioApi.configuration.api(:operations) { |api| api.default_access = :read_only }
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      api: :operations,
      operations: %i[index show],
      serializer: ->(recordable, **) { { name: recordable.name } },
      output_keys: %i[name]
    )
    RecordingStudioApi.register_action(
      :ops_ping,
      api: :operations,
      http_verb: :get,
      path: "ops-ping",
      handler: ->(_context) { { ok: true, api: "operations" } }
    )

    get "/recording_studio_api/apis/operations/v1/ops-ping", headers: authorization_headers
    assert_response :unauthorized

    operations_token = issue_operations_token
    get "/recording_studio_api/apis/operations/v1/ops-ping", headers: bearer_headers(operations_token)
    assert_response :success
    assert_equal "operations", JSON.parse(response.body).fetch("api")
  end

  test "recordable collection routes still work" do
    get "/recording_studio_api/api/v1/pages", headers: authorization_headers

    assert_response :success
    records = JSON.parse(response.body).fetch("records")
    assert_includes records.map { |record| record.fetch("id") }, @page_recording.id
  end

  test "openapi lists the registered action under the actions tag" do
    document = RecordingStudioApi::Services::OpenapiDocument.call

    ping = document.fetch(:paths).fetch("/recording_studio_api/api/v1/ping").fetch("get")
    assert_equal ["Actions"], ping.fetch(:tags)
    assert document.fetch(:paths).key?("/recording_studio_api/api/v1/pages")
    refute(document.fetch(:tags).any? { |tag| tag.fetch(:name) == "Ping" })
  end

  test "wrong verb is rejected for a registered path" do
    get "/recording_studio_api/api/v1/echo/widget", headers: authorization_headers

    assert_response :unprocessable_entity
    assert_equal "echo must be called with POST", JSON.parse(response.body).dig("error", "message")
  end

  private

  def authorization_headers
    bearer_headers(@access_token)
  end

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def issue_operations_token
    provision_result = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_point_recording: access_point_recording_for(@access_recording),
      manager_actor: access_manager_for(@access_recording),
      role: @access_recording.recordable.role,
      name: "Operations registered action client",
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
