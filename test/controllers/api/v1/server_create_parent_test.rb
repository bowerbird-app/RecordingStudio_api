# frozen_string_literal: true

require_relative "../../../support/api_dummy_helpers"

class ApiV1ServerCreateParentTest < ActionDispatch::IntegrationTest
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user, role: :edit)
    @access_token = issue_oauth_access_token_for(access_recording: @access_recording, name: "Server parent token")
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "default page create still requires parent_id and rejects an out of scope parent" do
    post page_path, params: { title: "Orphan page" }, headers: authorization_headers

    assert_response :unprocessable_entity
    assert_equal "parent_id is required for Page", JSON.parse(response.body).dig("error", "message")

    other_root, = create_access_recording_for(user: create_user(email: "outside-default-page@example.com"))
    assert_no_difference("Page.count") do
      post page_path, params: { title: "Scoped out", parent_id: other_root.id }, headers: authorization_headers
    end

    assert_response :not_found
    assert_equal "Parent resource was not found in this API scope", JSON.parse(response.body).dig("error", "message")
  end

  test "built-in create with a server parent succeeds without parent_id inside the api scope" do
    register_server_parent_folder!

    assert_difference("Folder.count", 1) do
      post folder_path, params: { name: "Filed folder" }, headers: authorization_headers
    end

    assert_response :created
    payload = JSON.parse(response.body)
    assert_equal "Filed folder", payload.fetch("name")
    assert_equal @root_recording.id, payload.fetch("parent_id")
    assert_equal @root_recording.id, payload.fetch("root_id")
    assert_catalog_omits_parent_id!("folders")
  end

  test "a client parent_id is ignored when the server chooses the parent" do
    register_server_parent_folder!
    decoy = nested_folder_recording("Decoy parent", @root_recording)

    post folder_path, params: { name: "Ignores parent", parent_id: decoy.id }, headers: authorization_headers

    assert_response :created
    assert_equal @root_recording.id, JSON.parse(response.body).fetch("parent_id")
    created = RecordingStudio::Recording.find(JSON.parse(response.body).fetch("id"))
    assert_equal @root_recording.id, created.parent_recording_id
  end

  test "a server parent outside the api scope is not found and creates nothing" do
    other_root, = create_access_recording_for(user: create_user(email: "outside-resolver@example.com"))
    register_server_parent_folder!(->(*) { other_root })

    assert_no_difference("Folder.count") do
      post folder_path, params: { name: "Blocked folder" }, headers: authorization_headers
    end

    assert_response :not_found
    assert_equal "Parent resource was not found in this API scope", JSON.parse(response.body).dig("error", "message")
  end

  test "server parent create replays an idempotency key and rejects a different body" do
    register_server_parent_folder!
    previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    key = "server-parent-#{SecureRandom.hex(8)}"
    headers = authorization_headers.merge("Idempotency-Key" => key)
    decoy = nested_folder_recording("Fingerprint decoy", @root_recording)

    begin
      RecordingStudioApi::IdempotencyStore.stub(:redis, nil) do
        assert_difference("Folder.count", 1) do
          post folder_path, params: { name: "First filed" }, headers: headers
        end
        assert_response :created
        first_id = JSON.parse(response.body).fetch("id")

        assert_no_difference("Folder.count") do
          post folder_path, params: { name: "First filed", parent_id: decoy.id }, headers: headers
        end
        assert_response :created
        assert_equal first_id, JSON.parse(response.body).fetch("id")

        assert_no_difference("Folder.count") do
          post folder_path, params: { name: "Different filed" }, headers: headers
        end
        assert_response :unprocessable_entity
        assert_equal "idempotency_key_reused", JSON.parse(response.body).dig("error", "code")
        assert_equal 0, Folder.where(name: "Different filed").count
      end
    ensure
      Rails.cache = previous_cache
    end
  end

  test "server parent create keeps authentication and authorization failures" do
    register_server_parent_folder!

    post folder_path, params: { name: "No token" }
    assert_response :unauthorized

    _view_root, view_access = create_access_recording_for(
      user: create_user(email: "view-server-parent@example.com"),
      role: :view
    )
    view_token = issue_oauth_access_token_for(access_recording: view_access, name: "View server parent")
    post folder_path, params: { name: "View blocked" }, headers: { "Authorization" => "Bearer #{view_token}" }
    assert_response :forbidden
    assert_equal 0, Folder.where(name: "View blocked").count

    RecordingStudioApi.configuration.api(:operations) { |api| api.default_access = :read_only }
    RecordingStudioApi.register_recordable_type_api("Workspace", api: :operations)
    operations_token = issue_operations_token
    post folder_path, params: { name: "Wrong api" }, headers: { "Authorization" => "Bearer #{operations_token}" }
    assert_response :unauthorized
    assert_equal 0, Folder.where(name: "Wrong api").count
  end

  test "a custom create handler with parent server receives a nil parent" do
    seen = :unset
    RecordingStudioApi.register_resource_handler("Page", :create, parent: :server, handler: lambda { |context|
      seen = context.parent_recording
      recording = context.root_recording.record(
        Page,
        actor: context.access_grant.actor,
        parent_recording: context.root_recording
      ) { |page| page.title = "Handler page" }
      { json: { id: recording.id, parent_id: recording.parent_recording_id.to_s }, status: :created }
    })

    assert_catalog_omits_parent_id!("pages")

    assert_difference("Page.count", 1) do
      post "/recording_studio_api/api/v1/pages", params: { title: "Handler page" }, headers: authorization_headers
    end

    assert_response :created
    assert_nil seen
    assert_equal @root_recording.id, JSON.parse(response.body).fetch("parent_id")
  end

  test "a creating capability action with parent server omits parent_id" do
    RecordingStudio.enable_capability(:notable, on: "Page")
    RecordingStudioApi.register_capability_action(
      :file_note,
      capability: :notable,
      creates: true,
      parent: :server,
      handler: ->(context) { { body: context.params[:body], seen_parent_id: context.params[:parent_id] } },
      serializer: ->(result) { result },
      input_contract: {
        fields: {
          body: { type: :string, required: true },
          parent_id: { type: :string, required: true }
        }
      }
    )
    RecordingStudioApi.register_recordable_type_api(
      "Page",
      serializer: ->(page, **) { { title: page.title } },
      output_keys: %i[title],
      capability_actions: %i[file_note]
    )
    page = create_page_recording(root_recording: @root_recording)

    post "/recording_studio_api/api/v1/pages/#{page.id}/actions/file_note",
         params: { body: "Hello", parent_id: "ignored" },
         headers: authorization_headers

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "Hello", payload.fetch("body")
    assert_nil payload.fetch("seen_parent_id")

    action = catalog_action_endpoint("pages", "file_note")
    assert_equal "server", action.fetch(:parent)
    schema = action.dig(:openapi, :request_body, :content, "application/json", :schema)
    refute schema.fetch(:properties).key?("parent_id")
    refute_includes Array(schema[:required]), "parent_id"

    document = RecordingStudioApi::Services::OpenapiDocument.call
    operation = document.dig(:paths, "/recording_studio_api/api/v1/pages/{id}/actions/file_note", "post")
    assert_equal "server", operation[:"x-parent"]
  end

  private

  def folder_path
    "/recording_studio_api/api/v1/folders"
  end

  def page_path
    "/recording_studio_api/api/v1/pages"
  end

  def authorization_headers
    { "Authorization" => "Bearer #{@access_token}" }
  end

  def register_server_parent_folder!(resolver = lambda(&:root_recording))
    RecordingStudioApi.register_recordable_type_api(
      "Folder",
      create_parent: :server,
      parent_resolver: resolver
    )
  end

  def assert_catalog_omits_parent_id!(resource_name)
    endpoint = catalog_create_endpoint(resource_name)
    schema = endpoint.dig(:openapi, :request_body, :content, "application/json", :schema)

    assert_equal "server", endpoint.fetch(:parent)
    refute schema.fetch(:properties).key?(:parent_id)
    refute_includes Array(schema.fetch(:required)), "parent_id"
    assert_includes endpoint.fetch(:description), "The server chooses the parent."
    assert_includes endpoint.fetch(:description), "A parent_id in the body is ignored."

    document = RecordingStudioApi::Services::OpenapiDocument.call
    operation = document.dig(:paths, "/recording_studio_api/api/v1/#{resource_name}", "post")
    assert_equal "server", operation[:"x-parent"]
    document_schema = operation.dig(:requestBody, :content, "application/json", :schema)
    refute document_schema.fetch(:properties).key?(:parent_id)
    refute_includes Array(document_schema.fetch(:required)), "parent_id"
  end

  def catalog_create_endpoint(resource_name)
    section = RecordingStudioApi::Services::DocumentationCatalog.call
                                                                .fetch(:resources)
                                                                .find { |resource| resource.fetch(:resource) == resource_name }
    section.fetch(:endpoints).find { |endpoint| endpoint.fetch(:action) == "resources#create" }
  end

  def catalog_action_endpoint(resource_name, action_name)
    section = RecordingStudioApi::Services::DocumentationCatalog.call
                                                                .fetch(:resources)
                                                                .find { |resource| resource.fetch(:resource) == resource_name }
    section.fetch(:endpoints).find { |endpoint| endpoint[:path].to_s.end_with?("/actions/#{action_name}") }
  end

  def issue_operations_token
    provision_result = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_point_recording: access_point_recording_for(@access_recording),
      manager_actor: access_manager_for(@access_recording),
      role: @access_recording.recordable.role,
      name: "Operations server parent client",
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
