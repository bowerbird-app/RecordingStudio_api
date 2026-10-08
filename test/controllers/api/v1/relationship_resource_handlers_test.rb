# frozen_string_literal: true

require_relative "../../../support/api_dummy_helpers"

class ApiV1RelationshipResourceHandlersTest < ActionDispatch::IntegrationTest
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user, role: :edit)
    @folder_recording = create_page_recording(root_recording: @root_recording).parent_recording
    @access_token = issue_oauth_access_token_for(access_recording: @access_recording, name: "Nested handler token")
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      relationships: {
        folders: {
          source: :children,
          child_type: "Folder",
          many: true,
          serializer: ->(recordable, **) { { name: recordable.name } },
          output_keys: %i[name],
          limit: 20,
          endpoints: %i[index show create update destroy]
        }
      }
    )
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "nested collection and member actions call a registered handler with raw ids" do
    calls = []
    %i[index show create update destroy].each do |action|
      RecordingStudioApi.register_resource_handler("Folder", action, handler: lambda { |context|
        calls << [
          action,
          context.recordable_type,
          context.parent_id,
          context.relationship_id,
          context.recording,
          context.parent_recording,
          context.class
        ]
        { json: { handled: action.to_s, parent_id: context.parent_id }, status: (action == :create ? :created : :ok) }
      })
    end
    folder_count = Folder.count
    name_before = @folder_recording.recordable.name

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders", headers: authorization_headers
    assert_response :success
    assert_equal "index", JSON.parse(response.body).fetch("handled")
    assert_equal @root_recording.id.to_s, JSON.parse(response.body).fetch("parent_id")

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders/#{@folder_recording.id}",
        headers: authorization_headers
    assert_response :success
    assert_equal "show", JSON.parse(response.body).fetch("handled")

    assert_no_difference("Folder.count") do
      post "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders",
           params: { name: "Should not be created" },
           headers: authorization_headers
    end
    assert_response :created
    assert_equal "create", JSON.parse(response.body).fetch("handled")
    assert_equal folder_count, Folder.count

    patch "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders/#{@folder_recording.id}",
          params: { name: "Should not be renamed" },
          headers: authorization_headers
    assert_response :success
    assert_equal "update", JSON.parse(response.body).fetch("handled")
    assert_equal name_before, @folder_recording.recordable.reload.name

    delete "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders/#{@folder_recording.id}",
           headers: authorization_headers
    assert_response :success
    assert_equal "destroy", JSON.parse(response.body).fetch("handled")
    assert RecordingStudio::Recording.exists?(@folder_recording.id)

    assert_equal [
      [:index, "Folder", @root_recording.id.to_s, nil, nil, nil, RecordingStudioApi::ResourceOperationContext],
      [:show, "Folder", @root_recording.id.to_s, @folder_recording.id.to_s, nil, nil, RecordingStudioApi::ResourceOperationContext],
      [:create, "Folder", @root_recording.id.to_s, nil, nil, nil, RecordingStudioApi::ResourceOperationContext],
      [:update, "Folder", @root_recording.id.to_s, @folder_recording.id.to_s, nil, nil, RecordingStudioApi::ResourceOperationContext],
      [:destroy, "Folder", @root_recording.id.to_s, @folder_recording.id.to_s, nil, nil, RecordingStudioApi::ResourceOperationContext]
    ], calls
  end

  test "nested routes keep ResourceOperations when no handler is registered" do
    create_called = false

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders", headers: authorization_headers
    assert_response :success
    payload = JSON.parse(response.body)
    assert payload.key?("records")
    refute payload.key?("handled")
    assert_includes payload.fetch("records").map { |record| record.fetch("id") }, @folder_recording.id

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders/#{@folder_recording.id}",
        headers: authorization_headers
    assert_response :success
    assert_equal @folder_recording.id, JSON.parse(response.body).fetch("id")
    refute JSON.parse(response.body).key?("handled")

    RecordingStudioApi::Services::ResourceOperations::Create.stub(:call, lambda { |context|
      create_called = true
      assert_equal @root_recording.id, context.parent_recording.id
      { json: { created_via: "shared", parent_id: context.parent_recording.id }, status: :created }
    }) do
      post "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders",
           params: { name: "Shared nested folder" },
           headers: authorization_headers
    end
    assert_response :created
    assert create_called
    assert_equal "shared", JSON.parse(response.body).fetch("created_via")

    RecordingStudioApi::Services::ResourceOperations::Update.stub(:call, lambda { |context|
      { json: { updated_via: "shared", id: context.recording.id }, status: :ok }
    }) do
      patch "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders/#{@folder_recording.id}",
            params: { name: "Shared rename" },
            headers: authorization_headers
    end
    assert_response :success
    assert_equal "shared", JSON.parse(response.body).fetch("updated_via")

    RecordingStudioApi::Services::ResourceOperations::Destroy.stub(:call, lambda { |context|
      { json: { deleted_via: "shared", id: context.recording.id }, status: :ok }
    }) do
      delete "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders/#{@folder_recording.id}",
             headers: authorization_headers
    end
    assert_response :success
    assert_equal "shared", JSON.parse(response.body).fetch("deleted_via")
    assert RecordingStudio::Recording.exists?(@folder_recording.id)
  end

  test "a nested handler owns access while unregistered nested routes still authorize the parent" do
    view_user = create_user
    view_root, view_access = create_access_recording_for(user: view_user, role: :view)
    view_folder = create_page_recording(root_recording: view_root).parent_recording
    view_token = issue_oauth_access_token_for(access_recording: view_access, name: "View nested token")
    view_headers = { "Authorization" => "Bearer #{view_token}" }
    RecordingStudioApi.register_resource_handler("Folder", :create, handler: lambda { |context|
      { json: { handled: "create", parent_id: context.parent_id }, status: :created }
    })

    post "/recording_studio_api/api/v1/workspaces/#{view_root.id}/folders",
         params: { name: "Handler owns this" },
         headers: view_headers
    assert_response :created
    assert_equal "create", JSON.parse(response.body).fetch("handled")
    assert_equal view_root.id.to_s, JSON.parse(response.body).fetch("parent_id")

    patch "/recording_studio_api/api/v1/workspaces/#{view_root.id}/folders/#{view_folder.id}",
          params: { name: "Blocked rename" },
          headers: view_headers
    assert_response :forbidden
  end

  test "a nested handler reaches a child outside the client's tree and an unregistered type still 404s" do
    operations_headers = operations_admin_headers
    workspace_root, folder_recording = out_of_tree_workspace_folder
    seen = []
    %i[index show create update destroy].each do |action|
      RecordingStudioApi.register_resource_handler("Folder", action, api: :operations, handler: lambda { |context|
        seen << [action, context.parent_id, context.relationship_id, context.recording, context.parent_recording]
        { json: { handled: action.to_s, parent_id: context.parent_id, relationship_id: context.relationship_id }, status: :ok }
      })
    end

    get "/recording_studio_api/apis/operations/v1/workspaces/#{workspace_root.id}/folders",
        headers: operations_headers
    assert_response :success
    assert_equal "index", JSON.parse(response.body).fetch("handled")

    get "/recording_studio_api/apis/operations/v1/workspaces/#{workspace_root.id}/folders/#{folder_recording.id}",
        headers: operations_headers
    assert_response :success
    assert_equal "show", JSON.parse(response.body).fetch("handled")
    assert_equal folder_recording.id.to_s, JSON.parse(response.body).fetch("relationship_id")

    post "/recording_studio_api/apis/operations/v1/workspaces/#{workspace_root.id}/folders",
         params: { name: "Outside tree" },
         headers: operations_headers
    assert_response :success
    assert_equal "create", JSON.parse(response.body).fetch("handled")

    patch "/recording_studio_api/apis/operations/v1/workspaces/#{workspace_root.id}/folders/#{folder_recording.id}",
          params: { name: "Outside rename" },
          headers: operations_headers
    assert_response :success
    assert_equal "update", JSON.parse(response.body).fetch("handled")

    delete "/recording_studio_api/apis/operations/v1/workspaces/#{workspace_root.id}/folders/#{folder_recording.id}",
           headers: operations_headers
    assert_response :success
    assert_equal "destroy", JSON.parse(response.body).fetch("handled")
    assert(seen.all? { |row| row[3].nil? && row[4].nil? })

    get "/recording_studio_api/apis/operations/v1/workspaces/#{workspace_root.id}/pages",
        headers: operations_headers
    assert_response :not_found
    assert_equal "Parent resource was not found in this API scope", JSON.parse(response.body).dig("error", "message")
  end

  private

  def operations_admin_headers
    configure_operations_api_with_nested_types!
    _admin_root, admin_root_recording = create_admin_root_recording(name: "Ops admin #{SecureRandom.hex(4)}")
    admin_access = grant_or_bootstrap_access!(recording: admin_root_recording, actor: @user, role: :admin)
    token = issue_named_api_token(access_recording: admin_access, api: :operations, name: "Ops nested token")
    { "Authorization" => "Bearer #{token}" }
  end

  def out_of_tree_workspace_folder
    workspace_root, = create_access_recording_for(user: create_user, workspace_name: "Support #{SecureRandom.hex(4)}")
    folder_recording = create_page_recording(root_recording: workspace_root).parent_recording
    [workspace_root, folder_recording]
  end

  def configure_operations_api_with_nested_types!
    RecordingStudioApi.configuration.api(:operations) { |api| api.default_access = :read_only }
    RecordingStudioApi.register_default_resource_actions!(api: :operations)
    RecordingStudioApi.register_default_capability_actions!(api: :operations)
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      api: :operations,
      operations: %i[index show],
      relationships: {
        folders: {
          source: :children,
          child_type: "Folder",
          many: true,
          serializer: ->(recordable, **) { { name: recordable.name } },
          output_keys: %i[name],
          limit: 20,
          endpoints: %i[index show create update destroy]
        },
        pages: {
          source: :children,
          child_type: "Page",
          many: true,
          serializer: ->(recordable, **) { { title: recordable.title } },
          output_keys: %i[title],
          limit: 20,
          endpoints: %i[index show]
        }
      }
    )
    RecordingStudioApi.register_recordable_type_api(
      "Folder",
      api: :operations,
      operations: %i[index show create update destroy],
      serializer: ->(recordable, **) { { name: recordable.name } },
      output_keys: %i[name]
    )
    RecordingStudioApi.register_recordable_type_api(
      "Page",
      api: :operations,
      operations: %i[index show],
      serializer: ->(recordable, **) { { title: recordable.title } },
      output_keys: %i[title]
    )
    RecordingStudioApi.register_recordable_type_api(
      "AdminRoot",
      api: :operations,
      operations: %i[index show],
      serializer: ->(recordable, **) { { name: recordable.name } },
      output_keys: %i[name]
    )
  end

  def issue_named_api_token(access_recording:, api:, name:)
    provision_result = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_point_recording: access_point_recording_for(access_recording),
      manager_actor: access_manager_for(access_recording),
      role: access_recording.recordable.role,
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

  def authorization_headers
    { "Authorization" => "Bearer #{@access_token}" }
  end
end
