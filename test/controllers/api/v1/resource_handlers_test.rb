# frozen_string_literal: true

require_relative "../../../support/api_dummy_helpers"

class ApiV1ResourceHandlersTest < ActionDispatch::IntegrationTest
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user, role: :edit)
    @page_recording = create_page_recording(root_recording: @root_recording)
    @folder_recording = @page_recording.parent_recording
    @access_token = issue_oauth_access_token_for(access_recording: @access_recording, name: "Handler token")
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "registered handlers run for each resource action and other types keep the shared handler" do
    calls = []
    %i[index show create update destroy].each do |action|
      RecordingStudioApi.register_resource_handler("Page", action, handler: lambda { |context|
        calls << [action, context.recordable_type, context.class]
        { json: { handled: action.to_s }, status: (action == :create ? :created : :ok) }
      })
    end
    title_before = @page_recording.recordable.title
    page_count = Page.count

    get "/recording_studio_api/api/v1/pages", headers: authorization_headers
    assert_response :success
    assert_equal "index", JSON.parse(response.body).fetch("handled")

    get "/recording_studio_api/api/v1/pages/#{@page_recording.id}", headers: authorization_headers
    assert_response :success
    assert_equal "show", JSON.parse(response.body).fetch("handled")

    assert_no_difference("Page.count") do
      post "/recording_studio_api/api/v1/pages", params: {
        parent_id: @folder_recording.id,
        title: "Should not be created"
      }, headers: authorization_headers
    end
    assert_response :created
    assert_equal "create", JSON.parse(response.body).fetch("handled")
    assert_equal page_count, Page.count

    patch "/recording_studio_api/api/v1/pages/#{@page_recording.id}", params: {
      title: "Should not be renamed"
    }, headers: authorization_headers
    assert_response :success
    assert_equal "update", JSON.parse(response.body).fetch("handled")
    assert_equal title_before, @page_recording.recordable.reload.title

    delete "/recording_studio_api/api/v1/pages/#{@page_recording.id}", headers: authorization_headers
    assert_response :success
    assert_equal "destroy", JSON.parse(response.body).fetch("handled")
    assert RecordingStudio::Recording.exists?(@page_recording.id)

    assert_equal [
      [:index, "Page", RecordingStudioApi::ResourceOperationContext],
      [:show, "Page", RecordingStudioApi::ResourceOperationContext],
      [:create, "Page", RecordingStudioApi::ResourceOperationContext],
      [:update, "Page", RecordingStudioApi::ResourceOperationContext],
      [:destroy, "Page", RecordingStudioApi::ResourceOperationContext]
    ], calls

    get "/recording_studio_api/api/v1/folders", headers: authorization_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert body.key?("records")
    assert_nil body["handled"]
    assert_includes body.fetch("records").map { |record| record.fetch("id") }, @folder_recording.id
  end

  test "a registered move handler runs and an unregistered type keeps shared move" do
    RecordingStudio.enable_capability(:movable, on: "Page")
    RecordingStudioApi.register_recordable_type_api("Page", capability_actions: %i[move])
    parent_id = @page_recording.parent_recording_id
    folder_parent_id = @folder_recording.parent_recording_id
    seen_context = nil
    RecordingStudioApi.register_resource_handler("Page", :move, handler: lambda { |context|
      seen_context = context
      { json: { handled: "move", parent_id: context.params[:parent_id] }, status: :accepted }
    })

    post "/recording_studio_api/api/v1/pages/#{@page_recording.id}/actions/move",
         params: { parent_id: @root_recording.id },
         headers: authorization_headers

    assert_response :accepted
    assert_equal "move", JSON.parse(response.body).fetch("handled")
    assert_equal @root_recording.id, JSON.parse(response.body).fetch("parent_id")
    assert_instance_of RecordingStudioApi::ActionContext, seen_context
    assert_equal parent_id, @page_recording.reload.parent_recording_id

    post "/recording_studio_api/api/v1/folders/#{@folder_recording.id}/actions/move",
         headers: authorization_headers

    assert_response :unprocessable_entity
    assert_equal "Invalid input for action move", JSON.parse(response.body).dig("error", "message")
    assert_nil JSON.parse(response.body)["handled"]
    assert_equal folder_parent_id, @folder_recording.reload.parent_recording_id
  end

  test "a per-type handler owns access and the shared handler still checks the role" do
    view_user = create_user
    view_root, view_access = create_access_recording_for(user: view_user, role: :view)
    view_page = create_page_recording(root_recording: view_root)
    view_token = issue_oauth_access_token_for(access_recording: view_access, name: "View token")
    headers = { "Authorization" => "Bearer #{view_token}" }

    RecordingStudio.enable_capability(:echoable, on: "Page")
    RecordingStudio.enable_capability(:echoable, on: "Workspace")
    RecordingStudioApi.register_capability_action(
      :echo,
      capability: :echoable,
      http_verb: :post,
      handler: ->(_context) { {} }
    )
    RecordingStudioApi.register_recordable_type_api("Page", capability_actions: %i[echo])
    RecordingStudioApi.register_recordable_type_api("Workspace", capability_actions: %i[echo])
    RecordingStudioApi.register_resource_handler("Page", :echo, handler: lambda { |_context|
      { json: { handled: "echo" }, status: :ok }
    })

    post "/recording_studio_api/api/v1/pages/#{view_page.id}/actions/echo", headers: headers
    assert_response :success
    assert_equal "echo", JSON.parse(response.body).fetch("handled")

    post "/recording_studio_api/api/v1/workspaces/#{view_root.id}/actions/echo", headers: headers
    assert_response :forbidden
  end

  test "handlers registered on one api do not run on the other" do
    RecordingStudioApi.configuration.api(:operations) { |api| api.default_access = :read_only }
    RecordingStudioApi.register_default_resource_actions!(api: :operations)
    RecordingStudioApi.register_default_capability_actions!(api: :operations)
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      api: :operations,
      operations: %i[index show]
    )
    RecordingStudioApi.register_recordable_type_api(
      "Page",
      api: :operations,
      operations: %i[index show create],
      serializer: ->(recordable, **) { { title: recordable.title } },
      output_keys: %i[title],
      writable_attributes: %i[title]
    )
    RecordingStudioApi.register_resource_handler("Page", :index, api: :operations, handler: lambda { |context|
      { json: { handled: "operations-index", api_key: context.api_key }, status: :ok }
    })
    RecordingStudioApi.register_resource_handler("Page", :create, api: :operations, handler: lambda { |context|
      { json: { handled: "operations-create", type: context.recordable_type }, status: :created }
    })
    RecordingStudioApi.register_resource_handler("Page", :show, handler: lambda { |_context|
      { json: { handled: "public-show" }, status: :ok }
    })

    get "/recording_studio_api/api/v1/pages", headers: authorization_headers
    assert_response :success
    assert JSON.parse(response.body).key?("records")
    assert_nil JSON.parse(response.body)["handled"]

    operations_token = issue_named_api_token(api: :operations, name: "Operations handler token")
    operations_headers = { "Authorization" => "Bearer #{operations_token}" }

    get "/recording_studio_api/apis/operations/v1/pages", headers: operations_headers
    assert_response :success
    assert_equal "operations-index", JSON.parse(response.body).fetch("handled")
    assert_equal "operations", JSON.parse(response.body).fetch("api_key")

    get "/recording_studio_api/apis/operations/v1/pages/#{@page_recording.id}", headers: operations_headers
    assert_response :success
    assert_equal @page_recording.recordable.title, JSON.parse(response.body).fetch("title")
    assert_nil JSON.parse(response.body)["handled"]

    get "/recording_studio_api/api/v1/pages/#{@page_recording.id}", headers: authorization_headers
    assert_response :success
    assert_equal "public-show", JSON.parse(response.body).fetch("handled")

    assert_no_difference("Page.count") do
      post "/recording_studio_api/apis/operations/v1/pages",
           params: { parent_id: @folder_recording.id, title: "Operations page" },
           headers: operations_headers
    end
    assert_response :created
    assert_equal "operations-create", JSON.parse(response.body).fetch("handled")
    assert_equal "Page", JSON.parse(response.body).fetch("type")
  end

  private

  def authorization_headers
    { "Authorization" => "Bearer #{@access_token}" }
  end

  def issue_named_api_token(api:, name:)
    provision_result = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_point_recording: access_point_recording_for(@access_recording),
      manager_actor: access_manager_for(@access_recording),
      role: @access_recording.recordable.role,
      name: name,
      api: api
    )
    raise provision_result.error unless provision_result.success?

    payload = provision_result.value
    token_result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: payload.fetch(:credential).oauth_client_id,
      client_secret: payload.fetch(:token),
      api: api
    )
    raise token_result.error unless token_result.success?

    token_result.value.fetch(:access_token)
  end
end
