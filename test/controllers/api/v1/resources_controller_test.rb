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
    assert_equal "Page", payload.fetch("type")
    assert_not_includes payload.keys, "attributes"
    assert payload.fetch("created_at")
    assert payload.fetch("updated_at")
  end

  test "expands the dummy Workspace relationship demonstration" do
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      relationships: {
        folders: {
          source: :children, child_type: "Folder", many: true, include: true,
          serializer: ->(folder, **) { { name: folder.name } }, output_keys: %i[name], limit: 20,
          endpoints: %i[index show]
        },
        pages: {
          source: :children, child_type: "Page", many: true, include: :request,
          serializer: ->(page, **) { { title: page.title } }, output_keys: %i[title], limit: 20,
          endpoints: %i[index show]
        },
        featured_folder: {
          source: :custom, many: false, include: :request,
          resolver: lambda do |context|
            context.scoped_recordings.where(
              parent_recording_id: context.recording.id,
              recordable_type: "Folder"
            ).order(:created_at, :id).first
          end,
          serializer: ->(folder, **) { { name: folder.name } }, output_keys: %i[name]
        }
      }
    )
    RecordingStudioApi.register_recordable_type_api(
      "Page",
      operations: %i[index show],
      serializer: ->(page, **) { { title: page.title } },
      output_keys: %i[title]
    )
    first_folder = RecordingStudio::Recording.create!(recordable: Folder.create!(name: "Included folder"), parent_recording: @root_recording)
    second_folder = RecordingStudio::Recording.create!(recordable: Folder.create!(name: "Featured folder"), parent_recording: @root_recording)
    first_page = RecordingStudio::Recording.create!(recordable: Page.create!(title: "Included page"), parent_recording: @root_recording)
    second_page = RecordingStudio::Recording.create!(recordable: Page.create!(title: "Second page"), parent_recording: @root_recording)

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}", headers: authorization_headers

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal([first_folder.id, second_folder.id], payload.fetch("folders").map { |folder| folder.fetch("id") })
    refute payload.key?("pages")
    refute payload.key?("featured_folder")

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}", params: { include: "pages" }, headers: authorization_headers

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal([first_page.id, second_page.id], payload.fetch("pages").map { |page| page.fetch("id") })
    refute payload.key?("featured_folder")

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}", params: { include: "featured_folder" }, headers: authorization_headers

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal first_folder.id, payload.fetch("featured_folder").fetch("id")
    refute payload.key?("pages")

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}", params: { include: "pages,featured_folder" }, headers: authorization_headers

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal([first_page.id, second_page.id], payload.fetch("pages").map { |page| page.fetch("id") })
    assert_equal first_folder.id, payload.fetch("featured_folder").fetch("id")

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders", headers: authorization_headers

    assert_response :success
    assert_equal([first_folder.id, second_folder.id], JSON.parse(response.body).fetch("records").map { |folder| folder.fetch("id") })

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/pages", headers: authorization_headers

    assert_response :success
    assert_equal([first_page.id, second_page.id], JSON.parse(response.body).fetch("records").map { |page| page.fetch("id") })

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}", params: { include: "unknown" }, headers: authorization_headers

    assert_response :unprocessable_entity

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/featured_folder", headers: authorization_headers

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body).fetch("error"), "featured_folder is not a direct child collection"
  end

  test "expands a request-driven named children relationship in the flat payload" do
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      relationships: {
        folders: { source: :children, child_type: "Folder", many: true, include: :request,
                   serializer: ->(recordable, **) { { name: recordable.name } }, output_keys: %i[name], limit: 20,
                   endpoints: %i[index show] }
      }
    )
    folder_recording = RecordingStudio::Recording.create!(
      recordable: Folder.create!(name: "Included folder"),
      parent_recording: @root_recording
    )

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}",
        params: { include: "folders" },
        headers: authorization_headers

    assert_response :success
    payload = JSON.parse(response.body)
    folders = payload.fetch("folders")

    assert_equal([folder_recording.id], folders.map { |child| child.fetch("id") })
    refute payload.key?("relationships")
    refute payload.key?("data")
  end

  test "enforces the flat API contract across includes, batching, and nested writes" do
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      fields: {
        status: { include: true, resolver: ->(_context) { "active" } },
        requested_label: { include: :request, resolver: ->(context) { "requested-#{context.recordable.name}" } }
      },
      relationships: {
        folders: {
          source: :children, child_type: "Folder", many: true, include: true, limit: 1,
          serializer: ->(folder, **) { { name: folder.name } }, output_keys: %i[name],
          endpoints: %i[index show create update]
        },
        featured_folder: {
          source: :custom, many: false, include: :request,
          resolver: ->(context) { context.scoped_recordings.where(parent_recording_id: context.recording.id, recordable_type: "Folder").order(:created_at, :id).first },
          serializer: ->(folder, **) { { name: folder.name } }, output_keys: %i[name]
        }
      }
    )
    second_workspace = RecordingStudio::Recording.create!(recordable: Workspace.create!(name: "Second"), parent_recording: @root_recording)
    first_folder = RecordingStudio::Recording.create!(recordable: Folder.create!(name: "First"), parent_recording: @root_recording)
    RecordingStudio::Recording.create!(recordable: Folder.create!(name: "Second folder"), parent_recording: @root_recording)
    second_folder = RecordingStudio::Recording.create!(recordable: Folder.create!(name: "Third"), parent_recording: second_workspace)

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}", headers: authorization_headers

    assert_response :success
    payload = JSON.parse(response.body)
    assert_flat_record(payload, @root_recording, type: "Workspace")
    assert payload.key?("name")
    assert_equal "active", payload.fetch("status")
    assert_equal([first_folder.id], payload.fetch("folders").map { |folder| folder.fetch("id") })
    assert_equal({ "limit" => 1, "has_more" => true }, payload.fetch("_meta").fetch("folders"))
    payload.fetch("folders").each do |folder|
      assert_equal "Folder", folder.fetch("type")
      assert_equal @root_recording.id, folder.fetch("parent_id")
    end
    refute payload.key?("requested_label")
    refute payload.key?("featured_folder")

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}",
        params: { include: "requested_label,featured_folder" }, headers: authorization_headers

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "requested-#{@root_recording.recordable.name}", payload.fetch("requested_label")
    assert_equal first_folder.id, payload.fetch("featured_folder").fetch("id")
    assert_equal "First", payload.fetch("featured_folder").fetch("name")

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}", params: { include: "unknown" }, headers: authorization_headers

    assert_response :unprocessable_entity

    get "/recording_studio_api/api/v1/workspaces", headers: authorization_headers

    assert_response :success
    records = JSON.parse(response.body).fetch("records")
    root_payload = records.find { |record| record.fetch("id") == @root_recording.id }
    second_payload = records.find { |record| record.fetch("id") == second_workspace.id }
    assert_equal({ "limit" => 1, "has_more" => true }, root_payload.fetch("_meta").fetch("folders"))
    assert_equal([first_folder.id], root_payload.fetch("folders").map { |folder| folder.fetch("id") })
    assert_equal([second_folder.id], second_payload.fetch("folders").map { |folder| folder.fetch("id") })
    refute second_payload.fetch("_meta", {}).key?("folders")

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders/#{first_folder.id}", headers: authorization_headers

    assert_response :success
    assert_flat_record(JSON.parse(response.body), first_folder, type: "Folder")

    patch "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders/#{first_folder.id}", params: {
      parent_id: second_workspace.id,
      attributes: { name: "Move attempt" }
    }, headers: authorization_headers

    assert_response :unprocessable_entity
    assert_equal @root_recording.id, first_folder.reload.parent_recording_id
  end

  test "shows a direct configured child relationship record with a flat payload" do
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      relationships: {
        folders: { source: :children, child_type: "Folder", many: true,
                   serializer: ->(recordable, **) { { name: recordable.name } }, output_keys: %i[name], limit: 20,
                   endpoints: %i[index show] }
      }
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
    assert_equal(
      RecordingStudioApi::Serializers::ResourceRecordingSerializer.call(
        folder_recording,
        version: "v1",
        api: "public"
      ).fetch(:type),
      payload.fetch("type")
    )
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
          many: false,
          resolver: ->(workspace) { { label: workspace.name } },
          serializer: ->(value, **) { value },
          output_keys: %i[label]
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
    assert_includes JSON.parse(response.body).fetch("error"), "summary is not a direct child collection"
  end

  test "rejects custom relationships from nested routing" do
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      relationships: {
        summary: {
          source: :custom,
          many: false,
          include: true,
          resolver: ->(workspace) { { label: workspace.name.upcase } },
          serializer: ->(value, **) { value },
          output_keys: %i[label]
        }
      }
    )

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/summary",
        headers: authorization_headers

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body).fetch("error"), "summary is not a direct child collection"
  end

  test "creates and updates declared children through a named relationship endpoint" do
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      relationships: {
        folders: { source: :children, child_type: "Folder", many: true,
                   serializer: ->(recordable, **) { { name: recordable.name } }, output_keys: %i[name], limit: 20,
                   endpoints: %i[index show create update] }
      }
    )

    post "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders", params: {
      attributes: { name: "Nested folder" }
    }, headers: authorization_headers

    assert_response :created
    child_id = JSON.parse(response.body).fetch("id")

    patch "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders/#{child_id}", params: {
      attributes: { name: "Renamed nested folder" }
    }, headers: authorization_headers

    assert_response :success
    assert_equal @root_recording.id, JSON.parse(response.body).fetch("parent_id")
  end

  test "does not expose writes for child relationships without a create endpoint" do
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      relationships: {
        folders: { source: :children, child_type: "Folder", many: true,
                   serializer: ->(recordable, **) { { name: recordable.name } }, output_keys: %i[name], limit: 20,
                   endpoints: %i[index show] }
      }
    )

    post "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders", params: {
      type: "folders",
      attributes: { name: "Blocked folder" }
    }, headers: authorization_headers

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body).fetch("error"), "create is not enabled for folders"
  end

  test "does not expose writes when the child registration disables create" do
    RecordingStudioApi.register_recordable_type_api(
      "Folder",
      operations: %i[index show update destroy]
    )
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      relationships: {
        folders: { source: :children, child_type: "Folder", many: true,
                   serializer: ->(recordable, **) { { name: recordable.name } }, output_keys: %i[name], limit: 20,
                   endpoints: %i[index show create update] }
      }
    )

    post "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders", params: {
      attributes: { name: "Blocked folder" }
    }, headers: authorization_headers

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body).fetch("error"), "create is not enabled for Folder"
  end

  test "does not resolve the direct child relationship before paginating nested index" do
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      relationships: {
        folders: {
          source: :children, child_type: "Folder", many: true,
          serializer: ->(recordable, **) { { name: recordable.name } }, output_keys: %i[name], limit: 20,
          endpoints: %i[index]
        }
      }
    )
    child = RecordingStudio::Recording.create!(recordable: Folder.create!(name: "Direct"), parent_recording: @root_recording)
    original = RecordingStudioApi::RelationshipContext.instance_method(:relationship_value)
    RecordingStudioApi::RelationshipContext.define_method(:relationship_value) do |*|
      raise "Nested structural index must not resolve the entire relationship"
    end

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders?limit=1", headers: authorization_headers

    assert_response :success
    assert_equal([child.id], JSON.parse(response.body).fetch("records").map { |record| record.fetch("id") })
  ensure
    RecordingStudioApi::RelationshipContext.define_method(:relationship_value, original) if original
  end

  test "conceals direct children rejected by relationship authorization" do
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      relationships: {
        folders: {
          source: :children, child_type: "Folder", many: true,
          serializer: ->(recordable, **) { { name: recordable.name } }, output_keys: %i[name], limit: 20,
          endpoints: %i[index show update destroy],
          authorize: ->(context) { context.target_recording.nil? }
        }
      }
    )
    denied = RecordingStudio::Recording.create!(recordable: Folder.create!(name: "Denied"), parent_recording: @root_recording)

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders", headers: authorization_headers
    assert_response :success
    assert_empty JSON.parse(response.body).fetch("records")

    [
      [:get, "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders/#{denied.id}"],
      [:patch, "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders/#{denied.id}"],
      [:delete, "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders/#{denied.id}"]
    ].each do |method, path|
      public_send(method, path, params: method == :patch ? { attributes: { name: "Hidden move" } } : {}, headers: authorization_headers)
      assert_response :not_found
    end
  end

  test "enforces nested member endpoint and child operation gates" do
    child = RecordingStudio::Recording.create!(recordable: Folder.create!(name: "Gated"), parent_recording: @root_recording)
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      relationships: {
        endpoint_folders: { source: :children, child_type: "Folder", many: true,
                            serializer: ->(recordable, **) { { name: recordable.name } }, output_keys: %i[name], limit: 20,
                            endpoints: %i[index] }
      }
    )

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/endpoint_folders/#{child.id}", headers: authorization_headers
    assert_response :unprocessable_entity
    patch "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/endpoint_folders/#{child.id}", params: { attributes: { name: "Blocked" } }, headers: authorization_headers
    assert_response :unprocessable_entity
    delete "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/endpoint_folders/#{child.id}", headers: authorization_headers
    assert_response :unprocessable_entity

    RecordingStudioApi.register_recordable_type_api("Folder", operations: %i[index show create])
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      relationships: {
        operation_folders: { source: :children, child_type: "Folder", many: true,
                             serializer: ->(recordable, **) { { name: recordable.name } }, output_keys: %i[name], limit: 20,
                             endpoints: %i[index show update destroy] }
      }
    )

    patch "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/operation_folders/#{child.id}", params: { attributes: { name: "Blocked" } }, headers: authorization_headers
    assert_response :unprocessable_entity
    delete "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/operation_folders/#{child.id}", headers: authorization_headers
    assert_response :unprocessable_entity
  end

  test "destroys a trashed direct child through the nested route" do
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      relationships: {
        folders: { source: :children, child_type: "Folder", many: true,
                   serializer: ->(recordable, **) { { name: recordable.name } }, output_keys: %i[name], limit: 20,
                   endpoints: %i[show destroy] }
      }
    )
    child = RecordingStudio::Recording.create!(recordable: Folder.create!(name: "Trashed"), parent_recording: @root_recording)
    child.update_column(:trashed_at, Time.current)

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders/#{child.id}", headers: authorization_headers
    assert_response :not_found

    delete "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders/#{child.id}", headers: authorization_headers
    assert_response :success
    assert_equal true, JSON.parse(response.body).fetch("deleted")
  end

  test "enforces nested relationship structure, type, and path parent" do
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      relationships: {
        folders: { source: :children, child_type: "Folder", many: true,
                   serializer: ->(recordable, **) { { name: recordable.name } }, output_keys: %i[name], limit: 20,
                   endpoints: %i[index show create update destroy] },
        owner: { source: :children, child_type: "Folder", many: false,
                 serializer: ->(recordable, **) { { name: recordable.name } }, output_keys: %i[name] }
      }
    )
    other_parent = RecordingStudio::Recording.create!(recordable: Workspace.create!(name: "Other"))
    direct_child = RecordingStudio::Recording.create!(recordable: Folder.create!(name: "Direct"), parent_recording: @root_recording)
    descendant = RecordingStudio::Recording.create!(recordable: Folder.create!(name: "Descendant"), parent_recording: direct_child)
    wrong_type = RecordingStudio::Recording.create!(recordable: Page.create!(title: "Wrong"), parent_recording: @root_recording)

    get "/recording_studio_api/api/v1/unknown/#{@root_recording.id}/folders", headers: authorization_headers
    assert_response :not_found

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/unknown", headers: authorization_headers
    assert_response :unprocessable_entity

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/owner", headers: authorization_headers
    assert_response :unprocessable_entity

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders", headers: authorization_headers
    assert_response :success
    assert_equal([direct_child.id], JSON.parse(response.body).fetch("records").map { |record| record.fetch("id") })

    [other_parent.id, descendant.id, wrong_type.id].each do |child_id|
      get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders/#{child_id}", headers: authorization_headers
      assert_response :not_found
    end

    post "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders", params: {
      type: "folders", attributes: { name: "Blocked type" }
    }, headers: authorization_headers
    assert_response :unprocessable_entity

    post "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders", params: {
      parent_id: other_parent.id, attributes: { name: "Blocked parent" }
    }, headers: authorization_headers
    assert_response :unprocessable_entity

    post "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders", params: {
      attributes: { name: "Created child" }
    }, headers: authorization_headers
    assert_response :created
    created = RecordingStudio::Recording.find(JSON.parse(response.body).fetch("id"))
    assert_equal @root_recording, created.parent_recording
    assert_equal "Folder", created.recordable_type

    patch "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders/#{direct_child.id}", params: {
      parent_id: other_parent.id, attributes: { name: "Move attempt" }
    }, headers: authorization_headers
    assert_response :unprocessable_entity
    assert_equal @root_recording, direct_child.reload.parent_recording

    delete "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders/#{created.id}", headers: authorization_headers
    assert_response :success
    assert_equal true, JSON.parse(response.body).fetch("deleted")
  end

  test "serves configured nested routes through a named API" do
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      relationships: {
        folders: { source: :children, child_type: "Folder", many: true,
                   serializer: ->(recordable, **) { { name: recordable.name } }, output_keys: %i[name], limit: 20,
                   endpoints: %i[index] }
      }
    )
    child = RecordingStudio::Recording.create!(recordable: Folder.create!(name: "Named"), parent_recording: @root_recording)

    get "/recording_studio_api/apis/public/v1/workspaces/#{@root_recording.id}/folders", headers: authorization_headers

    assert_response :success
    assert_equal([child.id], JSON.parse(response.body).fetch("records").map { |record| record.fetch("id") })
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
    assert_equal "Workspace", payload.fetch("type")
    assert_equal "Created Workspace", payload.fetch("name")
    assert_not_includes payload.keys, "unknown_attribute"
  end

  test "accepts flat writes, preserves legacy envelopes, and rejects ambiguous write bodies" do
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      relationships: {
        folders: { source: :children, child_type: "Folder", many: true,
                   serializer: ->(recordable, **) { { name: recordable.name } }, output_keys: %i[name], limit: 20,
                   endpoints: %i[create update] }
      }
    )

    post "/recording_studio_api/api/v1/folders", params: {
      name: "Flat top-level folder",
      parent_id: @root_recording.id
    }, headers: authorization_headers

    assert_response :created
    top_level_folder_id = JSON.parse(response.body).fetch("id")
    assert_equal "Flat top-level folder", RecordingStudio::Recording.find(top_level_folder_id).recordable.name

    post "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders", params: {
      name: "Flat nested folder"
    }, headers: authorization_headers

    assert_response :created
    nested_folder_id = JSON.parse(response.body).fetch("id")

    patch "/recording_studio_api/api/v1/folders/#{top_level_folder_id}", params: {
      name: "Flat renamed folder",
      created_at: 1.year.ago.iso8601
    }, headers: authorization_headers

    assert_response :success
    top_level_folder = RecordingStudio::Recording.find(top_level_folder_id).recordable
    assert_equal "Flat renamed folder", top_level_folder.name
    assert_not_equal 1.year.ago.iso8601, top_level_folder.created_at.iso8601

    post "/recording_studio_api/api/v1/workspaces", params: {
      attributes: { name: "Legacy workspace" }
    }, headers: authorization_headers

    assert_response :created
    legacy_workspace_id = JSON.parse(response.body).fetch("id")

    patch "/recording_studio_api/api/v1/folders/#{nested_folder_id}", params: {
      attributes: { name: "Legacy renamed folder" }
    }, headers: authorization_headers

    assert_response :success
    assert_equal "Legacy renamed folder", RecordingStudio::Recording.find(nested_folder_id).recordable.name

    post "/recording_studio_api/api/v1/folders", params: {
      name: "Mixed folder",
      parent_id: @root_recording.id,
      attributes: { name: "Legacy mixed folder" }
    }, headers: authorization_headers

    assert_response :unprocessable_entity
    assert_equal "Use either flat writable fields or attributes, not both", JSON.parse(response.body).fetch("error")

    patch "/recording_studio_api/api/v1/workspaces/#{legacy_workspace_id}", params: {
      parent_id: @root_recording.id
    }, headers: authorization_headers

    assert_response :unprocessable_entity
    assert_equal "parent_id is not permitted for updates; use the move action instead", JSON.parse(response.body).fetch("error")
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
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      writable_attributes: %i[name],
      immutable_fields: %i[name]
    )
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

  def assert_flat_record(payload, recording, type:)
    assert_equal recording.id, payload.fetch("id")
    assert_equal type, payload.fetch("type")
    assert_nullable_equal recording.parent_recording_id, payload.fetch("parent_id")
    assert_nullable_equal recording.root_recording_id, payload.fetch("root_id")
    assert_match(/\A\d{4}-\d{2}-\d{2}T/, payload.fetch("created_at"))
    assert_match(/\A\d{4}-\d{2}-\d{2}T/, payload.fetch("updated_at"))
    %w[attributes relationships data actions].each { |key| refute payload.key?(key) }
  end

  def assert_nullable_equal(expected, actual)
    return assert_nil actual if expected.nil?

    assert_equal expected, actual
  end

  def authorization_headers
    { "Authorization" => "Bearer #{@access_token}" }
  end
end
