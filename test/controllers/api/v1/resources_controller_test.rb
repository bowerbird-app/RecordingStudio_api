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
    RecordingStudioApi::Concerns::RateLimiting.decider = nil
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "does not throttle api v1 requests when api throttling is disabled" do
    RecordingStudioApi.configuration.rate_limit_api_enabled = false
    RecordingStudioApi::Concerns::RateLimiting.decider = lambda do |controller|
      {
        limited: controller.send(:rate_limit_enabled_for_request?),
        limit: 1,
        remaining: 0,
        retry_after: 30
      }
    end

    get "/recording_studio_api/api/v1/pages", headers: authorization_headers

    assert_response :success
  end

  test "rejects resource requests before rate limiting or authentication when API access is disabled" do
    RecordingStudioApi::ApiSetting.find_or_create_by!(key: "api")
                                  .update!(api_access_enabled: false)
    rate_limit_checked = false
    RecordingStudioApi::Concerns::RateLimiting.decider = lambda do
      rate_limit_checked = true
      { limited: true, limit: 1, remaining: 0, retry_after: 30 }
    end

    get "/recording_studio_api/api/v1/pages", headers: { "Authorization" => "Bearer invalid-token" }

    assert_response :service_unavailable
    assert_not rate_limit_checked
    assert_equal "api_access_disabled", JSON.parse(response.body).fetch("error")
  end

  test "throttles api v1 read requests when api throttling is enabled" do
    RecordingStudioApi.configuration.rate_limit_api_enabled = true
    RecordingStudioApi::Concerns::RateLimiting.decider = lambda do |controller|
      {
        limited: controller.send(:rate_limit_bucket) == "api_read",
        limit: 5,
        remaining: 0,
        retry_after: 15
      }
    end

    get "/recording_studio_api/api/v1/pages", headers: authorization_headers

    assert_response :too_many_requests
    assert_equal "15", response.headers["Retry-After"]
    assert_equal "5", response.headers["X-RateLimit-Limit"]
    assert_equal "0", response.headers["X-RateLimit-Remaining"]
  end

  test "throttles api v1 write requests when api throttling is enabled" do
    RecordingStudioApi.configuration.rate_limit_api_enabled = true
    RecordingStudioApi::Concerns::RateLimiting.decider = lambda do |controller|
      {
        limited: controller.send(:rate_limit_bucket) == "api_write",
        limit: 3,
        remaining: 0,
        retry_after: 9
      }
    end

    post "/recording_studio_api/api/v1/workspaces", params: {
      attributes: {
        name: "Throttled Workspace"
      }
    }, headers: authorization_headers

    assert_response :too_many_requests
    assert_equal "9", response.headers["Retry-After"]
    assert_equal "3", response.headers["X-RateLimit-Limit"]
    assert_equal "0", response.headers["X-RateLimit-Remaining"]
  end

  test "paginates collection responses with pagination_token" do
    first_page = create_page_recording(root_recording: @root_recording, page_title: "First page")
    second_page = create_page_recording(root_recording: @root_recording, page_title: "Second page")
    third_page = create_page_recording(root_recording: @root_recording, page_title: "Third page")
    now = Time.current
    first_page.update_columns(created_at: now, updated_at: now)
    second_page.update_columns(created_at: now, updated_at: now)
    third_page.update_columns(created_at: now, updated_at: now)

    get "/recording_studio_api/api/v1/pages", params: { limit: 2 }, headers: authorization_headers

    assert_response :success

    first_payload = JSON.parse(response.body)
    first_meta = first_payload.fetch("meta")
    first_page_ids = first_payload.fetch("records").map { |row| row.fetch("id") }

    assert_equal 2, first_meta.fetch("limit")
    assert_equal "created_at", first_meta.fetch("sort")
    assert_equal "asc", first_meta.fetch("order")
    assert_equal true, first_meta.fetch("has_more")
    refute_nil first_meta.fetch("next_pagination_token")

    get "/recording_studio_api/api/v1/pages", params: { limit: 2, pagination_token: first_meta.fetch("next_pagination_token") }, headers: authorization_headers

    assert_response :success

    second_payload = JSON.parse(response.body)
    second_meta = second_payload.fetch("meta")
    second_page_ids = second_payload.fetch("records").map { |row| row.fetch("id") }

    assert_equal false, second_meta.fetch("has_more")
    assert_nil second_meta.fetch("next_pagination_token")
    expected_ids = [first_page.id, second_page.id, third_page.id].sort
    assert_equal expected_ids, (first_page_ids + second_page_ids).sort
    assert_empty(first_page_ids & second_page_ids)
  end

  test "returns unprocessable entity for invalid pagination token" do
    get "/recording_studio_api/api/v1/pages", params: { pagination_token: "not-a-valid-token" }, headers: authorization_headers

    assert_response :unprocessable_entity
    assert_equal "Invalid pagination token", JSON.parse(response.body).fetch("error")
  end

  test "returns unprocessable entity for a tampered pagination token" do
    3.times { |index| create_page_recording(root_recording: @root_recording, page_title: "Page #{index}") }

    get "/recording_studio_api/api/v1/pages", params: { limit: 2 }, headers: authorization_headers

    assert_response :success
    pagination_token = JSON.parse(response.body).dig("meta", "next_pagination_token")
    refute_nil pagination_token

    tampered_token = pagination_token.dup
    tampered_token[-1] = tampered_token.end_with?("a") ? "b" : "a"

    get "/recording_studio_api/api/v1/pages", params: { limit: 2, pagination_token: tampered_token }, headers: authorization_headers

    assert_response :unprocessable_entity
    assert_equal "Invalid pagination token", JSON.parse(response.body).fetch("error")
  end

  test "sorts workspace collection using configured recordable sortable attributes" do
    workspace_a = Workspace.create!(name: "Alpha sort workspace")
    workspace_z = Workspace.create!(name: "Zulu sort workspace")
    workspace_a_recording = RecordingStudio::Recording.create!(recordable: workspace_a, parent_recording: @root_recording)
    workspace_z_recording = RecordingStudio::Recording.create!(recordable: workspace_z, parent_recording: @root_recording)

    get "/recording_studio_api/api/v1/workspaces", params: { sort: "name", order: "asc" }, headers: authorization_headers

    assert_response :success

    payload = JSON.parse(response.body)
    records = payload.fetch("records")
    workspace_ids = records.map { |row| row.fetch("id") }
    workspace_names = records.map { |row| row.fetch("name") }

    assert_equal "name", payload.fetch("meta").fetch("sort")
    assert workspace_ids.include?(workspace_a_recording.id)
    assert workspace_ids.include?(workspace_z_recording.id)
    assert_operator workspace_names.index("Alpha sort workspace"), :<, workspace_names.index("Zulu sort workspace")
  end

  test "rejects sort attributes that are not configured for the requested resource" do
    get "/recording_studio_api/api/v1/workspaces", params: { sort: "title" }, headers: authorization_headers

    assert_response :unprocessable_entity
    assert_equal "sort must be one of: created_at, name", JSON.parse(response.body).fetch("error")
  end

  test "serializes default payload for page resources" do
    page_recording = create_page_recording(root_recording: @root_recording, page_title: "Docs Landing")

    get "/recording_studio_api/api/v1/pages/#{page_recording.id}", headers: authorization_headers

    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal page_recording.id, payload.fetch("id")
    assert_equal "page", payload.fetch("type")
    assert_not_includes payload.keys, "attributes"
    assert payload.fetch("created_at")
    assert payload.fetch("updated_at")
  end

  test "expands a request-driven named children relationship in the flat payload" do
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      relationships: { folders: { source: :children, types: ["Folder"], include: :request } }
    )
    folder_recording = RecordingStudio::Recording.create!(
      recordable: Folder.create!(name: "Included folder"),
      parent_recording: @root_recording
    )

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}",
        params: { include: true },
        headers: authorization_headers

    assert_response :success
    payload = JSON.parse(response.body)
    folders = payload.fetch("folders")

    assert_equal [folder_recording.id], folders.map { |child| child.fetch("id") }
    refute payload.key?("relationships")
    refute payload.key?("data")
  end

  test "shows a direct configured child relationship record with a flat payload" do
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      relationships: { folders: { source: :children, types: ["Folder"] } }
    )
    folder_recording = RecordingStudio::Recording.create!(
      recordable: Folder.create!(name: "Direct child"),
      parent_recording: @root_recording
    )

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders/#{folder_recording.id}",
        headers: authorization_headers

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal folder_recording.id, payload.fetch("id")
    assert_equal "folder", payload.fetch("type")
    assert_equal "Direct child", payload.fetch("name")
    refute payload.key?("data")
    refute payload.key?("attributes")
  end

  test "does not expose direct records through a custom relationship" do
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      relationships: {
        summary: {
          source: :custom,
          resolver: ->(workspace) { { label: workspace.name } },
          output_keys: %i[label],
          fields: { label: :label }
        }
      }
    )
    folder_recording = RecordingStudio::Recording.create!(
      recordable: Folder.create!(name: "Not a custom relationship child"),
      parent_recording: @root_recording
    )

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/summary/#{folder_recording.id}",
        headers: authorization_headers

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body).fetch("error"), "summary is not a child relationship"
  end

  test "exposes a named custom relationship without a relationship wrapper" do
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      relationships: {
        summary: {
          source: :custom,
          include: true,
          resolver: ->(workspace) { { label: workspace.name.upcase } },
          output_keys: %i[label],
          fields: { label: :label }
        }
      }
    )

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}", headers: authorization_headers

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal({ "label" => @root_recording.recordable.name.upcase }, payload.fetch("summary"))
    refute payload.key?("relationships")

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/summary",
        headers: authorization_headers

    assert_response :success
    assert_equal(
      [{ "label" => @root_recording.recordable.name.upcase }],
      JSON.parse(response.body).fetch("records")
    )
  end

  test "creates and updates declared children through a named relationship endpoint" do
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      relationships: { folders: { source: :children, types: ["Folder"], write: true } }
    )

    post "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders", params: {
      type: "folders",
      attributes: { name: "Nested folder" }
    }, headers: authorization_headers

    assert_response :created
    child_id = JSON.parse(response.body).fetch("id")

    patch "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders/#{child_id}", params: {
      attributes: { name: "Renamed nested folder" }
    }, headers: authorization_headers

    assert_response :success
    assert_equal "Renamed nested folder", RecordingStudio::Recording.find(child_id).recordable.name
  end

  test "does not expose writes for immutable named relationships" do
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      relationships: { folders: { source: :children, types: ["Folder"], write: true } },
      immutable_relationships: %i[folders]
    )

    post "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders", params: {
      type: "folders",
      attributes: { name: "Blocked folder" }
    }, headers: authorization_headers

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body).fetch("error"), "folders is immutable"
  end

  test "lists available API resources when no resource param is provided" do
    get "/recording_studio_api/api/v1", headers: authorization_headers

    assert_response :success

    resources = JSON.parse(response.body).fetch("resources")
    names = resources.map { |entry| entry.fetch("name") }

    assert_includes names, "workspaces"
    assert_includes names, "folders"
  end

  test "creates a scoped workspace resource and filters unknown attributes" do
    post "/recording_studio_api/api/v1/workspaces", params: {
      attributes: {
        name: "Created Workspace",
        unknown_attribute: "ignored"
      }
    }, headers: authorization_headers

    assert_response :created

    payload = JSON.parse(response.body)
    assert_equal "workspace", payload.fetch("type")
    assert_equal "Created Workspace", payload.fetch("name")
    assert_not_includes payload.keys, "unknown_attribute"
  end

  test "rejects resource operations excluded by a recordable allowlist" do
    RecordingStudioApi.register_recordable_type_api("Workspace", operations: %i[index])

    get "/recording_studio_api/api/v1/workspaces", headers: authorization_headers

    assert_response :success

    post "/recording_studio_api/api/v1/workspaces", params: {
      attributes: { name: "Excluded workspace" }
    }, headers: authorization_headers

    assert_response :unprocessable_entity
    assert_equal "create is not enabled for Workspace", JSON.parse(response.body).fetch("error")
  end

  test "does not make response-only OpenAPI properties writable" do
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      openapi: {
        details_schema: {
          properties: {
            created_at: { type: "string", format: "date-time" }
          }
        }
      }
    )
    workspace_recording = RecordingStudio::Recording.create!(
      recordable: Workspace.create!(name: "Original"),
      parent_recording: @root_recording
    )
    requested_created_at = 1.year.ago.iso8601

    patch "/recording_studio_api/api/v1/workspaces/#{workspace_recording.id}", params: {
      attributes: {
        name: "Updated",
        created_at: requested_created_at
      }
    }, headers: authorization_headers

    assert_response :success
    workspace = workspace_recording.reload.recordable
    assert_equal "Updated", workspace.name
    assert_not_equal requested_created_at, workspace.created_at.iso8601
  end

  test "allows immutable fields on create but ignores them on update" do
    RecordingStudioApi.register_recordable_type_api("Workspace", immutable_fields: %i[name])
    original_name = @root_recording.recordable.name

    patch "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}", params: {
      attributes: { name: "Attempted rename" }
    }, headers: authorization_headers

    assert_response :success
    assert_equal original_name, @root_recording.recordable.reload.name

    post "/recording_studio_api/api/v1/workspaces", params: {
      attributes: { name: "Write-once workspace" }
    }, headers: authorization_headers

    assert_response :created
    assert_equal "Write-once workspace", JSON.parse(response.body).fetch("name")
  end

  test "returns validation errors when creating a page without a title" do
    post "/recording_studio_api/api/v1/pages", params: {
      parent_id: @root_recording.id,
      attributes: {
        additionalProperty: "anything"
      }
    }, headers: authorization_headers

    assert_response :unprocessable_entity

    payload = JSON.parse(response.body)
    assert_equal "Title can't be blank", payload.fetch("error")
    assert_equal [
      {
        "attribute" => "title",
        "message" => "can't be blank",
        "full_message" => "Title can't be blank",
        "type" => "blank"
      }
    ], payload.fetch("details")
  end

  test "requires parent_id when creating a non-root page resource" do
    post "/recording_studio_api/api/v1/pages", params: {
      attributes: {
        title: "Orphan page"
      }
    }, headers: authorization_headers

    assert_response :unprocessable_entity

    payload = JSON.parse(response.body)
    assert_equal "parent_id is required for Page", payload.fetch("error")
    assert_equal [
      {
        "attribute" => "parent_id",
        "message" => "is required",
        "full_message" => "Parent is required",
        "type" => "blank"
      }
    ], payload.fetch("details")
  end

  test "rejects create when parent type is not allowed and rolls back recordable creation" do
    page_recording = create_page_recording(root_recording: @root_recording, page_title: "Invalid parent")
    folders_before = Folder.count

    post "/recording_studio_api/api/v1/folders", params: {
      parent_id: page_recording.id,
      attributes: {
        name: "Invalid Child Folder"
      }
    }, headers: authorization_headers

    assert_response :unprocessable_entity

    payload = JSON.parse(response.body)
    assert_equal "Folder cannot be recorded under Page", payload.fetch("error")
    assert_equal folders_before, Folder.count
    assert_equal [
      {
        "attribute" => "parent_id",
        "message" => "is not allowed for Folder",
        "full_message" => "Folder cannot be recorded under Page",
        "type" => "invalid"
      }
    ], payload.fetch("details")
  end

  test "ignores update attributes for unregistered page resources" do
    page_recording = create_page_recording(root_recording: @root_recording)
    original_title = page_recording.recordable.title

    patch "/recording_studio_api/api/v1/pages/#{page_recording.id}", params: {
      attributes: {
        title: ""
      }
    }, headers: authorization_headers

    assert_response :success

    assert_equal original_title, page_recording.recordable.reload.title
    assert_not_includes JSON.parse(response.body).keys, "attributes"
  end

  test "rejects create when parent is outside authenticated scope" do
    other_root_recording, = create_access_recording_for(user: create_user(email: "outside-create@example.com"))

    post "/recording_studio_api/api/v1/workspaces", params: {
      parent_id: other_root_recording.id,
      attributes: {
        name: "Blocked Workspace"
      }
    }, headers: authorization_headers

    assert_response :not_found
    assert_equal "Parent resource was not found in this API scope", JSON.parse(response.body).fetch("error")
  end

  test "rejects show when recording type does not match requested resource" do
    folder_recording = RecordingStudio::Recording.create!(
      recordable: Folder.create!(name: "Type mismatch folder"),
      parent_recording: @root_recording
    )

    get "/recording_studio_api/api/v1/pages/#{folder_recording.id}", headers: authorization_headers

    assert_response :not_found
    assert_includes JSON.parse(response.body).fetch("error"), "Resource type does not match"
  end

  test "rejects unknown API resource" do
    get "/recording_studio_api/api/v1/unknown_resources", headers: authorization_headers

    assert_response :not_found
    assert_equal "Unknown API resource unknown_resources", JSON.parse(response.body).fetch("error")
  end

  test "rejects a resource outside the authenticated root scope" do
    other_root_recording, = create_access_recording_for(user: create_user(email: "outside-root-resources@example.com"))
    hidden_page = create_page_recording(root_recording: other_root_recording)

    get "/recording_studio_api/api/v1/pages/#{hidden_page.id}", headers: authorization_headers

    assert_response :not_found
    assert_equal "Resource was not found in this API scope", JSON.parse(response.body).fetch("error")
  end

  test "deletes a resource by hard deleting its recording" do
    page_recording = create_page_recording(root_recording: @root_recording)

    delete "/recording_studio_api/api/v1/pages/#{page_recording.id}", headers: authorization_headers

    assert_response :success
    payload = JSON.parse(response.body)

    assert_equal page_recording.id, payload.fetch("id")
    assert_equal true, payload.fetch("deleted")
    assert_equal "destroyed", payload.fetch("deleted_via")
    assert_nil RecordingStudio::Recording.unscoped.find_by(id: page_recording.id)

    get "/recording_studio_api/api/v1/pages/#{page_recording.id}", headers: authorization_headers
    assert_response :not_found
  end

  test "forbids create for clients with view-only access" do
    _view_root_recording, view_access_recording = create_access_recording_for(
      user: create_user(email: "view-only-create@example.com"),
      role: :view
    )
    view_token = issue_oauth_access_token_for(access_recording: view_access_recording, name: "View-only token")

    post "/recording_studio_api/api/v1/workspaces", params: {
      attributes: {
        name: "Blocked Workspace"
      }
    }, headers: { "Authorization" => "Bearer #{view_token}" }

    assert_response :forbidden
    assert_equal "API access grant is not authorized for this capability", JSON.parse(response.body).fetch("error")
  end

  test "view token cannot inherit another access recording owned by the same actor" do
    user = create_user(email: "view-token-other-access@example.com")
    root_recording, view_access_recording = create_access_recording_for(user: user, role: :view)
    with_access_creation_context do
      admin_access = RecordingStudio::Access.create!(actor: user, role: :admin)
      RecordingStudio::Recording.create!(recordable: admin_access, parent_recording: root_recording)
    end
    view_token = issue_oauth_access_token_for(access_recording: view_access_recording, name: "View token with sibling admin")

    post "/recording_studio_api/api/v1/workspaces", params: {
      attributes: {
        name: "Blocked Workspace"
      }
    }, headers: { "Authorization" => "Bearer #{view_token}" }

    assert_response :forbidden
    assert_equal "API access grant is not authorized for this capability", JSON.parse(response.body).fetch("error")
  end

  test "forbids update for clients with view-only access" do
    _view_root_recording, view_access_recording = create_access_recording_for(
      user: create_user(email: "view-only-update@example.com"),
      role: :view
    )
    page_recording = create_page_recording(root_recording: view_access_recording.root_recording)
    view_token = issue_oauth_access_token_for(access_recording: view_access_recording, name: "View-only token")

    patch "/recording_studio_api/api/v1/pages/#{page_recording.id}", params: {
      attributes: {
        title: "Blocked Update"
      }
    }, headers: { "Authorization" => "Bearer #{view_token}" }

    assert_response :forbidden
    assert_equal "API access grant is not authorized for this capability", JSON.parse(response.body).fetch("error")
  end

  test "forbids destroy for clients with view-only access" do
    _view_root_recording, view_access_recording = create_access_recording_for(
      user: create_user(email: "view-only-destroy@example.com"),
      role: :view
    )
    page_recording = create_page_recording(root_recording: view_access_recording.root_recording)
    view_token = issue_oauth_access_token_for(access_recording: view_access_recording, name: "View-only token")

    delete "/recording_studio_api/api/v1/pages/#{page_recording.id}", headers: { "Authorization" => "Bearer #{view_token}" }

    assert_response :forbidden
    assert_equal "API access grant is not authorized for this capability", JSON.parse(response.body).fetch("error")
  end

  test "rejects delete for resources outside the authenticated root scope" do
    other_root_recording, = create_access_recording_for(user: create_user(email: "outside-delete@example.com"))
    hidden_page = create_page_recording(root_recording: other_root_recording)

    delete "/recording_studio_api/api/v1/pages/#{hidden_page.id}", headers: authorization_headers

    assert_response :not_found
    assert_equal "Resource was not found in this API scope", JSON.parse(response.body).fetch("error")
  end

  private

  def authorization_headers
    { "Authorization" => "Bearer #{@access_token}" }
  end
end
