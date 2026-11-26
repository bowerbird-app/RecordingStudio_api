# frozen_string_literal: true

require_relative "../../../support/api_dummy_helpers"

class ApiV1RegisteredHandlerScopeTest < ActionDispatch::IntegrationTest
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user, role: :edit)
    @page_recording = create_page_recording(root_recording: @root_recording)
    @folder_recording = @page_recording.parent_recording
    @access_token = issue_oauth_access_token_for(access_recording: @access_recording, name: "Scope token")
    @foreign_root, = create_access_recording_for(user: create_user, workspace_name: "Foreign #{SecureRandom.hex(4)}")
    @foreign_page = create_page_recording(root_recording: @foreign_root)
    @foreign_folder = @foreign_page.parent_recording
    @calls = []
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "a foreign id returns 404 and the handler does not run" do
    register_page_show
    register_member_echo
    register_nested_folders
    register_scoped_endpoint

    get "/recording_studio_api/api/v1/pages/#{@foreign_page.id}", headers: headers
    assert_response :not_found
    assert_equal api_scope_missing_message("Page"), JSON.parse(response.body).dig("error", "message")

    post "/recording_studio_api/api/v1/pages/#{@foreign_page.id}/actions/echo", headers: headers
    assert_response :not_found

    get "/recording_studio_api/api/v1/workspaces/#{@foreign_root.id}/folders/#{@foreign_folder.id}", headers: headers
    assert_response :not_found
    assert_equal "Parent resource was not found in this API scope", JSON.parse(response.body).dig("error", "message")

    get "/recording_studio_api/api/v1/scoped-pages/#{@foreign_page.id}", headers: headers
    assert_response :not_found
    assert_empty @calls

    get "/recording_studio_api/api/v1/pages/#{@page_recording.id}", headers: headers
    assert_response :success
    assert_equal @page_recording.id, @calls.last[:recording_id]

    post "/recording_studio_api/api/v1/pages/#{@page_recording.id}/actions/echo", headers: headers
    assert_response :success
    assert_equal @page_recording.id, @calls.last[:recording_id]
    assert_equal @page_recording.id.to_s, @calls.last[:id]

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders/#{@folder_recording.id}", headers: headers
    assert_response :success
    assert_equal @folder_recording.id, @calls.last[:recording_id]
    assert_equal @root_recording.id, @calls.last[:parent_recording_id]

    get "/recording_studio_api/api/v1/scoped-pages/#{@page_recording.id}", headers: headers
    assert_response :success
    assert_equal @page_recording.id, @calls.last[:recording_id]
    assert_equal 4, @calls.size
  end

  test "a wrong type returns 404 and the handler does not run" do
    register_page_show
    register_scoped_endpoint

    get "/recording_studio_api/api/v1/pages/#{@folder_recording.id}", headers: headers
    assert_response :not_found
    assert_equal "Expected a Page, but this id is a Folder. Pass the id of a Page recording (the id returned when that resource was created or looked up).", JSON.parse(response.body).dig("error", "message")

    get "/recording_studio_api/api/v1/scoped-pages/#{@folder_recording.id}", headers: headers
    assert_response :not_found
    assert_equal "Expected a Page, but this id is a Folder. Pass the id of a Page recording (the id returned when that resource was created or looked up).", JSON.parse(response.body).dig("error", "message")
    assert_empty @calls
  end

  test "a trashed recording is 404 when the handler does not include trashed rows" do
    @page_recording.update_column(:trashed_at, Time.current)
    register_page_show
    RecordingStudioApi.register_endpoint(
      :kept_page,
      http_verb: :get,
      path: "kept-pages/:id",
      recordable_type: "Page",
      handler: endpoint_probe("kept")
    )

    get "/recording_studio_api/api/v1/pages/#{@page_recording.id}", headers: headers
    assert_response :not_found

    get "/recording_studio_api/api/v1/kept-pages/#{@page_recording.id}", headers: headers
    assert_response :not_found
    assert_empty @calls
  end

  test "include_trashed returns the trashed recording to the handler" do
    @page_recording.update_column(:trashed_at, Time.current)
    RecordingStudioApi.register_resource_handler("Page", :show, include_trashed: true, handler: probe("show"))
    RecordingStudioApi.register_endpoint(
      :trashed_page,
      http_verb: :get,
      path: "trashed-pages/:id",
      recordable_type: "Page",
      include_trashed: true,
      handler: endpoint_probe("trashed")
    )

    get "/recording_studio_api/api/v1/pages/#{@page_recording.id}", headers: headers
    assert_response :success
    assert_equal @page_recording.id, @calls.last[:recording_id]

    get "/recording_studio_api/api/v1/trashed-pages/#{@page_recording.id}", headers: headers
    assert_response :success
    assert_equal @page_recording.id, @calls.last[:recording_id]
  end

  test "a member action can include a trashed recording when the action says so" do
    enable_echo
    @page_recording.update_column(:trashed_at, Time.current)
    RecordingStudioApi.register_capability_action(
      :touch,
      capability: :echoable,
      http_verb: :post,
      handler: ->(context) { { recording_id: context.recording&.id } },
      serializer: ->(result) { result }
    )
    RecordingStudioApi.register_capability_action(
      :restore,
      capability: :echoable,
      http_verb: :post,
      include_trashed: true,
      handler: ->(context) { { recording_id: context.recording&.id } },
      serializer: ->(result) { result }
    )
    RecordingStudioApi.register_recordable_type_api("Page", capability_actions: %i[touch restore])

    post "/recording_studio_api/api/v1/pages/#{@page_recording.id}/actions/touch", headers: headers
    assert_response :not_found

    post "/recording_studio_api/api/v1/pages/#{@page_recording.id}/actions/restore", headers: headers
    assert_response :success
    assert_equal @page_recording.id, JSON.parse(response.body).fetch("recording_id")
  end

  test "show is allowed for a view grant and update is not" do
    view_headers, view_page = view_client
    RecordingStudioApi.register_resource_handler("Page", :show, handler: probe("show"))
    RecordingStudioApi.register_resource_handler("Page", :update, handler: probe("update"))

    get "/recording_studio_api/api/v1/pages/#{view_page.id}", headers: view_headers
    assert_response :success
    assert_equal(["show"], @calls.map { |call| call[:name] })

    patch "/recording_studio_api/api/v1/pages/#{view_page.id}", params: { title: "Nope" }, headers: view_headers
    assert_response :forbidden
    assert_equal unauthorized_role_message(:edit), JSON.parse(response.body).dig("error", "message")
    assert_equal(["show"], @calls.map { |call| call[:name] })

    patch "/recording_studio_api/api/v1/pages/#{@page_recording.id}", params: { title: "Ok" }, headers: headers
    assert_response :success
    assert_equal @page_recording.id, @calls.last[:recording_id]
    assert_equal "update", @calls.last[:name]
  end

  test "an endpoint patch requires edit and a get requires view" do
    view_headers, view_page = view_client
    RecordingStudioApi.register_endpoint(
      :read_page,
      http_verb: :get,
      path: "role-pages/:id",
      recordable_type: "Page",
      handler: endpoint_probe("read")
    )
    RecordingStudioApi.register_endpoint(
      :write_page,
      http_verb: :patch,
      path: "role-pages/:id",
      recordable_type: "Page",
      handler: endpoint_probe("write")
    )

    get "/recording_studio_api/api/v1/role-pages/#{view_page.id}", headers: view_headers
    assert_response :success
    assert_equal view_page.id, @calls.last[:recording_id]

    patch "/recording_studio_api/api/v1/role-pages/#{view_page.id}",
          params: { title: "Nope" },
          as: :json,
          headers: view_headers
    assert_response :forbidden
    assert_equal(["read"], @calls.map { |call| call[:name] })

    patch "/recording_studio_api/api/v1/role-pages/#{@page_recording.id}",
          params: { title: "Ok" },
          as: :json,
          headers: headers
    assert_response :success
    assert_equal @page_recording.id, @calls.last[:recording_id]
  end

  test "owns_scoping on a read action runs for another root and a write resolves an owned id" do
    RecordingStudioApi.register_resource_handler("Page", :show, owns_scoping: true, handler: probe("show"))
    RecordingStudioApi.register_resource_handler("Page", :update, owns_scoping: true, handler: owned_write("update"))
    RecordingStudio.enable_capability(:echoable, on: "Page")
    RecordingStudioApi.register_capability_action(
      :published,
      capability: :echoable,
      http_verb: :get,
      required_role: :view,
      owns_scoping: true,
      handler: ->(context) { { recording_id: context.recording&.id, id: context.id } },
      serializer: ->(result) { result }
    )
    RecordingStudioApi.register_capability_action(
      :echo,
      capability: :echoable,
      http_verb: :post,
      owns_scoping: true,
      handler: owned_capability_write("echo"),
      serializer: ->(result) { result }
    )
    RecordingStudioApi.register_recordable_type_api("Page", capability_actions: %i[published echo])
    RecordingStudioApi.register_endpoint(
      :public_page,
      http_verb: :get,
      path: "public-pages/:id",
      recordable_type: "Page",
      owns_scoping: true,
      handler: endpoint_probe("public")
    )
    RecordingStudioApi.register_endpoint(
      :write_owned,
      http_verb: :patch,
      path: "owned-pages/:id",
      recordable_type: "Page",
      owns_scoping: true,
      handler: owned_endpoint_write("owned")
    )

    get "/recording_studio_api/api/v1/pages/#{@foreign_page.id}", headers: headers
    assert_response :success
    assert_nil @calls.last[:recording_id]
    assert_equal @foreign_page.id.to_s, @calls.last[:id]

    get "/recording_studio_api/api/v1/pages/#{@foreign_page.id}/actions/published", headers: headers
    assert_response :success
    assert_nil JSON.parse(response.body).fetch("recording_id")
    assert_equal @foreign_page.id.to_s, JSON.parse(response.body).fetch("id")

    get "/recording_studio_api/api/v1/public-pages/#{@foreign_page.id}", headers: headers
    assert_response :success
    assert_nil @calls.last[:recording_id]
    assert_equal @foreign_page.id.to_s, @calls.last[:params_id]

    patch "/recording_studio_api/api/v1/pages/#{@page_recording.recordable_id}",
          params: { title: "Owned" },
          as: :json,
          headers: headers
    assert_response :success
    assert_equal "update", @calls.last[:name]
    assert_equal @page_recording.id, @calls.last[:recording_id]

    post "/recording_studio_api/api/v1/pages/#{@page_recording.recordable_id}/actions/echo", headers: headers
    assert_response :success
    assert_equal @page_recording.id, JSON.parse(response.body).fetch("recording_id")

    patch "/recording_studio_api/api/v1/owned-pages/#{@page_recording.recordable_id}",
          params: { title: "Owned" },
          as: :json,
          headers: headers
    assert_response :success
    assert_equal @page_recording.id, @calls.last[:recording_id]

    calls_after_owned = @calls.size
    patch "/recording_studio_api/api/v1/pages/#{@foreign_page.recordable_id}",
          params: { title: "Nope" },
          as: :json,
          headers: headers
    assert_response :not_found
    assert_equal api_scope_missing_message("Page"), JSON.parse(response.body).dig("error", "message")
    assert_equal calls_after_owned, @calls.size

    post "/recording_studio_api/api/v1/pages/#{@foreign_page.id}/actions/echo", headers: headers
    assert_response :not_found
    assert_equal calls_after_owned, @calls.size

    patch "/recording_studio_api/api/v1/owned-pages/#{SecureRandom.uuid}",
          params: { title: "Nope" },
          as: :json,
          headers: headers
    assert_response :not_found
    assert_equal calls_after_owned, @calls.size

    view_headers, view_page = view_client
    patch "/recording_studio_api/api/v1/pages/#{view_page.recordable_id}",
          params: { title: "Nope" },
          as: :json,
          headers: view_headers
    assert_response :forbidden
    assert_equal unauthorized_role_message(:edit), JSON.parse(response.body).dig("error", "message")
    assert_equal calls_after_owned, @calls.size

    destroy_write = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.register_resource_handler("Page", :destroy, owns_scoping: true, handler: probe("destroy"))
    end
    unscoped_write = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.register_endpoint(
        :write_public,
        http_verb: :post,
        path: "public-pages",
        owns_scoping: true,
        handler: ->(_context) { {} }
      )
    end
    assert_includes destroy_write.message, "owns_scoping is only allowed on a read action"
    assert_includes unscoped_write.message, "owns_scoping is only allowed on a read action"

    create_write = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.register_resource_handler("Folder", :create, owns_scoping: true, handler: probe("create"))
    end
    assert_includes create_write.message, "owns_scoping is only allowed on a read action"

    register_nested_folders
    RecordingStudioApi.register_resource_handler("Folder", :update, owns_scoping: true, handler: probe("nested-update"))
    patch "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders/#{@foreign_folder.id}",
          params: { name: "Nope" },
          as: :json,
          headers: headers
    assert_response :not_found
    assert_equal calls_after_owned, @calls.size

    patch "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders/#{@folder_recording.id}",
          params: { name: "Kept" },
          as: :json,
          headers: headers
    assert_response :success
    assert_equal @folder_recording.id, @calls.last[:recording_id]
  end

  test "a nested index scopes the route parent and a flat create leaves the body parent id" do
    register_nested_folders
    RecordingStudioApi.register_resource_handler("Folder", :index, handler: probe("index"))
    RecordingStudioApi.register_resource_handler("Page", :create, handler: probe("create"))

    get "/recording_studio_api/api/v1/workspaces/#{@foreign_root.id}/folders", headers: headers
    assert_response :not_found
    assert_empty @calls

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders", headers: headers
    assert_response :success
    assert_nil @calls.last[:recording_id]
    assert_equal @root_recording.id, @calls.last[:parent_recording_id]
    assert_equal @root_recording.id.to_s, @calls.last[:parent_id]

    post "/recording_studio_api/api/v1/pages",
         params: { parent_id: @foreign_folder.id, title: "Elsewhere" },
         headers: headers
    assert_response :created
    assert_nil @calls.last[:parent_recording_id]
    assert_equal @foreign_folder.id.to_s, @calls.last[:parent_id].to_s
  end

  test "a move handler receives the scoped member and the raw destination id" do
    RecordingStudio.enable_capability(:movable, on: "Page")
    RecordingStudioApi.register_recordable_type_api("Page", capability_actions: %i[move])
    RecordingStudioApi.register_resource_handler("Page", :move, handler: probe("move"))

    post "/recording_studio_api/api/v1/pages/#{@page_recording.id}/actions/move",
         params: { parent_id: @foreign_folder.id },
         headers: headers
    assert_response :success
    assert_equal @page_recording.id, @calls.last[:recording_id]
    assert_equal @foreign_folder.id.to_s, @calls.last[:params_parent_id].to_s
  end

  test "an endpoint cannot capture both id and recording_id" do
    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.register_endpoint(
        :both_ids,
        http_verb: :get,
        path: "pages/:recording_id/copies/:id",
        recordable_type: "Page",
        handler: endpoint_probe("both")
      )
    end
    assert_includes error.message, "cannot capture both :id and :recording_id"

    opted_out = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.register_endpoint(
        :both_ids,
        http_verb: :get,
        path: "pages/:id/copies/:recording_id",
        scope_id: false,
        handler: endpoint_probe("both")
      )
    end
    assert_includes opted_out.message, "cannot capture both :id and :recording_id"
  end

  test "a nested handler rejects a relationship that is not a direct child collection" do
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      relationships: {
        folder: {
          source: :children,
          child_type: "Folder",
          many: false,
          serializer: ->(recordable, **) { { name: recordable.name } },
          output_keys: %i[name]
        }
      }
    )
    RecordingStudioApi.register_resource_handler("Folder", :show, handler: probe("nested-show"))

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folder/#{@folder_recording.id}", headers: headers
    assert_response :unprocessable_entity
    assert_equal "folder is not a direct child collection", JSON.parse(response.body).dig("error", "message")
    assert_empty @calls
  end

  test "a nested handler rejects an operation the relationship does not enable" do
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
          endpoints: %i[index]
        }
      }
    )
    RecordingStudioApi.register_resource_handler("Folder", :show, handler: probe("nested-show"))

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders/#{@folder_recording.id}", headers: headers
    assert_response :unprocessable_entity
    assert_equal "show is not enabled for folders", JSON.parse(response.body).dig("error", "message")
    assert_empty @calls
  end

  test "an endpoint id requires a recordable type unless scope_id is false" do
    missing = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.register_endpoint(
        :person,
        http_verb: :get,
        path: "people/:id",
        handler: endpoint_probe("person")
      )
    end
    assert_includes missing.message, "scope_id: false"

    RecordingStudioApi.register_endpoint(
      :person,
      http_verb: :get,
      path: "people/:id",
      scope_id: false,
      handler: endpoint_probe("person")
    )
    RecordingStudioApi.register_endpoint(
      :recording_page,
      http_verb: :get,
      path: "recordings/:recording_id",
      recordable_type: "Page",
      handler: endpoint_probe("recording")
    )

    get "/recording_studio_api/api/v1/people/#{@foreign_page.id}", headers: headers
    assert_response :success
    assert_nil @calls.last[:recording_id]
    assert_equal @foreign_page.id.to_s, @calls.last[:params_id]

    get "/recording_studio_api/api/v1/recordings/#{@foreign_page.id}", headers: headers
    assert_response :not_found
    assert_equal 1, @calls.size

    get "/recording_studio_api/api/v1/recordings/#{@page_recording.id}", headers: headers
    assert_response :success
    assert_equal @page_recording.id, @calls.last[:recording_id]
  end

  test "an unscoped write refuses a view key and accepts an edit key" do
    view_headers, = view_client
    edit_headers, = role_client(:edit, "Edit unscoped token")
    register_unscoped_role_endpoints

    get "/recording_studio_api/api/v1/notes", headers: view_headers
    assert_response :success
    assert_equal "list", @calls.last[:name]
    assert_nil @calls.last[:recording_id]

    post "/recording_studio_api/api/v1/notes", headers: view_headers, as: :json
    assert_response :forbidden
    assert_equal "forbidden", JSON.parse(response.body).dig("error", "code")
    assert_equal unauthorized_role_message(:edit), JSON.parse(response.body).dig("error", "message")

    patch "/recording_studio_api/api/v1/notes", headers: view_headers, as: :json
    assert_response :forbidden

    delete "/recording_studio_api/api/v1/people/person-1", headers: view_headers
    assert_response :forbidden
    assert_equal(["list"], @calls.map { |call| call[:name] })

    post "/recording_studio_api/api/v1/notes", headers: edit_headers, as: :json
    assert_response :success
    assert_nil @calls.last[:recording_id]
    assert_equal "create", @calls.last[:name]

    patch "/recording_studio_api/api/v1/notes", headers: edit_headers, as: :json
    assert_response :success
    assert_equal "revise", @calls.last[:name]
    assert_nil @calls.last[:recording_id]

    delete "/recording_studio_api/api/v1/people/person-1", headers: edit_headers
    assert_response :success
    assert_equal "remove", @calls.last[:name]
    assert_nil @calls.last[:recording_id]

    post "/recording_studio_api/api/v1/notifications/note-1/mark-read", headers: view_headers, as: :json
    assert_response :success
    assert_equal "mark_read", @calls.last[:name]
    assert_nil @calls.last[:recording_id]
    assert_equal "note-1", @calls.last[:params_id]
  end

  test "an unscoped endpoint denies a key whose owner lost access" do
    owner = create_user
    root, owner_access = create_access_recording_for(user: owner, role: :admin)
    other = create_user
    grant_or_bootstrap_access!(recording: root, actor: other, role: :admin)
    provisioned = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_point_recording: root,
      manager_actor: owner,
      role: :edit,
      name: "Owner unscoped key"
    )
    assert provisioned.success?
    issued = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: provisioned.value.fetch(:credential).oauth_client_id,
      client_secret: provisioned.value.fetch(:token)
    )
    assert issued.success?
    assert_equal owner, provisioned.value.fetch(:api_client).owner
    bearer = { "Authorization" => "Bearer #{issued.value.fetch(:access_token)}" }

    RecordingStudioApi.register_endpoint(
      :owner_note,
      http_verb: :post,
      path: "owner-notes",
      handler: endpoint_probe("owner_note")
    )

    post "/recording_studio_api/api/v1/owner-notes", headers: bearer, as: :json
    assert_response :success
    assert_equal(["owner_note"], @calls.map { |call| call[:name] })

    revoked = RecordingStudioAccessible::Services::RevokeRecordingAccess.call(
      recording: root,
      access_recording: owner_access,
      manager_actor: other,
      allow_last_admin_removal: true
    )
    assert revoked.success?

    @calls.clear
    post "/recording_studio_api/api/v1/owner-notes", headers: bearer, as: :json
    assert_response :forbidden
    assert_equal unauthorized_role_message(:edit), JSON.parse(response.body).dig("error", "message")
    assert_empty @calls
  end

  test "a post endpoint can require view and a post read cannot opt out of scoping" do
    view_headers, view_page = view_client
    RecordingStudioApi.register_endpoint(
      :search_page,
      http_verb: :post,
      path: "search-pages/:id",
      recordable_type: "Page",
      required_role: :view,
      handler: endpoint_probe("search")
    )
    RecordingStudioApi.register_endpoint(
      :edit_page,
      http_verb: :post,
      path: "edit-pages/:id",
      recordable_type: "Page",
      handler: endpoint_probe("edit")
    )

    post "/recording_studio_api/api/v1/search-pages/#{view_page.id}", headers: view_headers
    assert_response :success
    assert_equal view_page.id, @calls.last[:recording_id]

    post "/recording_studio_api/api/v1/edit-pages/#{view_page.id}", headers: view_headers
    assert_response :forbidden
    assert_equal 1, @calls.size

    view_opt_out = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.register_capability_action(
        :search,
        capability: :echoable,
        http_verb: :post,
        required_role: :view,
        owns_scoping: true,
        handler: ->(_context) { {} }
      )
    end
    assert_includes view_opt_out.message, "owns_scoping is only allowed on a read action"

    unscoped_post = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.register_capability_action(
        :unscoped_post,
        capability: :echoable,
        http_verb: :post,
        scope: :collection,
        owns_scoping: true,
        handler: ->(_context) { {} }
      )
    end
    assert_includes unscoped_post.message, "owns_scoping is only allowed on a read action"
  end

  test "a later edit role revokes owns_scoping before the handler runs" do
    enable_echo
    RecordingStudioApi.register_capability_action(
      :published,
      capability: :echoable,
      http_verb: :get,
      required_role: :view,
      owns_scoping: true,
      handler: ->(context) { { recording_id: context.recording&.id } },
      serializer: ->(result) { result }
    )
    RecordingStudioApi.register_recordable_type_api("Page", capability_actions: %i[published])
    RecordingStudioApi.configuration.capability_action_roles = { "published" => :edit }

    get "/recording_studio_api/api/v1/pages/#{@foreign_page.id}/actions/published", headers: headers
    assert_response :not_found

    get "/recording_studio_api/api/v1/pages/#{@page_recording.id}/actions/published", headers: headers
    assert_response :success
    assert_equal @page_recording.id, JSON.parse(response.body).fetch("recording_id")

    view_headers, view_page = view_client
    get "/recording_studio_api/api/v1/pages/#{view_page.id}/actions/published", headers: view_headers
    assert_response :forbidden
  end

  test "include_trashed is rejected on a write that is not restore or destroy" do
    update_handler = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.register_resource_handler("Page", :update, include_trashed: true, handler: probe("update"))
    end
    enable_echo
    echo_handler = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.register_capability_action(
        :echo,
        capability: :echoable,
        http_verb: :post,
        include_trashed: true,
        handler: ->(_context) { {} }
      )
    end
    endpoint = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.register_endpoint(
        :write_page,
        http_verb: :post,
        path: "write-pages/:id",
        recordable_type: "Page",
        include_trashed: true,
        handler: endpoint_probe("write")
      )
    end
    RecordingStudioApi.register_resource_handler("Page", :destroy, include_trashed: true, handler: probe("destroy"))

    assert_includes update_handler.message, "include_trashed is only allowed on a read, restore, or destroy action"
    assert_includes echo_handler.message, "include_trashed is only allowed on a read, restore, or destroy action"
    assert_includes endpoint.message, "include_trashed is only allowed on a read, restore, or destroy action"
  end

  test "a custom post with trashed_semantics resolves an in-scope trashed recording" do
    @page_recording.update_column(:trashed_at, Time.current)
    @foreign_page.update_column(:trashed_at, Time.current)
    register_restore_action

    post restore_path(@page_recording), headers: headers
    assert_response :success
    assert_equal @page_recording.id, JSON.parse(response.body).fetch("recording_id")

    post restore_path(@foreign_page), headers: headers
    assert_response :not_found
    assert_equal api_scope_missing_message("Page"), JSON.parse(response.body).dig("error", "message")

    view_headers, view_page = view_client
    view_page.update_column(:trashed_at, Time.current)
    post restore_path(view_page), headers: view_headers
    assert_response :forbidden
    assert_equal unauthorized_role_message(:edit), JSON.parse(response.body).dig("error", "message")
    recording_ids = @calls.map { |call| call[:recording_id] }
    assert_equal [@page_recording.id], recording_ids
  end

  test "trashed_semantics is required for a custom post and rejected for view, owns_scoping, or get" do
    enable_echo
    missing = assert_raises(RecordingStudioApi::ConfigurationError) do
      register_capability_action(:trashable_restore, include_trashed: true)
    end
    view_role = assert_raises(RecordingStudioApi::ConfigurationError) do
      register_capability_action(:trashable_restore, required_role: :view, include_trashed: true, trashed_semantics: :restore)
    end
    scoping = assert_raises(RecordingStudioApi::ConfigurationError) do
      register_capability_action(:trashable_restore, required_role: :edit, owns_scoping: true, trashed_semantics: :restore)
    end
    get_action = assert_raises(RecordingStudioApi::ConfigurationError) do
      register_capability_action(:trashable_restore, http_verb: :get, required_role: :edit, include_trashed: true, trashed_semantics: :restore)
    end
    unknown = assert_raises(RecordingStudioApi::ConfigurationError) do
      register_capability_action(:trashable_restore, trashed_semantics: :purge)
    end
    endpoint_get = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.register_endpoint(
        :get_restore,
        http_verb: :get,
        path: "get-restore/:id",
        recordable_type: "Page",
        required_role: :edit,
        include_trashed: true,
        trashed_semantics: :restore,
        handler: endpoint_probe("get")
      )
    end
    endpoint_view = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.register_endpoint(
        :view_restore,
        http_verb: :post,
        path: "view-restore/:id",
        recordable_type: "Page",
        required_role: :view,
        include_trashed: true,
        trashed_semantics: :restore,
        handler: endpoint_probe("view")
      )
    end
    endpoint_scope = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.register_endpoint(
        :scoped_restore,
        http_verb: :post,
        path: "scoped-restore/:id",
        recordable_type: "Page",
        owns_scoping: true,
        trashed_semantics: :restore,
        handler: endpoint_probe("scoped")
      )
    end
    show_handler = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.register_resource_handler("Page", :show, trashed_semantics: :restore, handler: probe("show"))
    end
    RecordingStudioApi.register_capability_action(
      :peek,
      capability: :echoable,
      http_verb: :post,
      required_role: :view,
      handler: ->(_context) { {} }
    )
    handler_view = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.register_resource_handler(
        "Page",
        :peek,
        include_trashed: true,
        trashed_semantics: :restore,
        handler: probe("peek")
      )
    end
    register_capability_action(:trashable_restore)
    handler_missing = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.register_resource_handler(
        "Page",
        :trashable_restore,
        include_trashed: true,
        handler: probe("restore")
      )
    end
    unregistered = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.register_resource_handler(
        "Page",
        :not_registered,
        trashed_semantics: :destroy,
        handler: probe("missing")
      )
    end

    assert_includes missing.message, "include_trashed is only allowed on a read, restore, or destroy action"
    assert_includes view_role.message, "trashed_semantics requires a role of :edit or higher"
    assert_includes scoping.message, "trashed_semantics is not allowed with owns_scoping"
    assert_includes get_action.message, "trashed_semantics is not allowed on a GET"
    assert_includes unknown.message, "trashed_semantics must be :restore or :destroy"
    assert_includes endpoint_get.message, "trashed_semantics is not allowed on a GET"
    assert_includes endpoint_view.message, "trashed_semantics requires a role of :edit or higher"
    assert_includes endpoint_scope.message, "trashed_semantics is not allowed with owns_scoping"
    assert_includes show_handler.message, "trashed_semantics is not allowed on a GET"
    assert_includes handler_view.message, "trashed_semantics requires a role of :edit or higher"
    assert_includes handler_missing.message, "include_trashed is only allowed on a read, restore, or destroy action"
    assert_includes unregistered.message, "trashed_semantics requires a registered non-GET action"

    register_capability_action(
      :trashable_purge,
      required_role: :admin,
      include_trashed: true,
      trashed_semantics: :destroy
    )
  end

  test "a resource handler and endpoint with trashed_semantics return a trashed recording" do
    @page_recording.update_column(:trashed_at, Time.current)
    @foreign_page.update_column(:trashed_at, Time.current)
    enable_echo
    RecordingStudioApi.register_capability_action(
      :trashable_restore,
      capability: :echoable,
      http_verb: :post,
      include_trashed: true,
      trashed_semantics: :restore,
      handler: ->(_context) { { via: "action" } },
      serializer: ->(result) { result }
    )
    RecordingStudioApi.register_recordable_type_api("Page", capability_actions: %i[trashable_restore])
    RecordingStudioApi.register_resource_handler(
      "Page",
      :trashable_restore,
      include_trashed: true,
      trashed_semantics: :restore,
      handler: probe("restore")
    )
    RecordingStudioApi.register_endpoint(
      :purge_page,
      http_verb: :post,
      path: "purge-pages/:id",
      recordable_type: "Page",
      include_trashed: true,
      trashed_semantics: :destroy,
      handler: endpoint_probe("purge")
    )

    post restore_path(@page_recording), headers: headers
    assert_response :success
    assert_equal "restore", @calls.last[:name]
    assert_equal @page_recording.id, @calls.last[:recording_id]

    post "/recording_studio_api/api/v1/purge-pages/#{@foreign_page.id}", headers: headers
    assert_response :not_found
    names_after_foreign = @calls.map { |call| call[:name] }
    assert_equal ["restore"], names_after_foreign

    post "/recording_studio_api/api/v1/purge-pages/#{@page_recording.id}", headers: headers
    assert_response :success
    assert_equal @page_recording.id, @calls.last[:recording_id]
    assert_equal "purge", @calls.last[:name]

    view_headers, view_page = view_client
    view_page.update_column(:trashed_at, Time.current)
    post "/recording_studio_api/api/v1/purge-pages/#{view_page.id}", headers: view_headers
    assert_response :forbidden
    names_after_view = @calls.map { |call| call[:name] }
    assert_equal %w[restore purge], names_after_view
  end

  test "a later view role does not include trashed recordings for a declared restore" do
    register_restore_action
    RecordingStudioApi.configuration.capability_action_roles = { "trashable_restore" => :view }
    @page_recording.update_column(:trashed_at, Time.current)

    post restore_path(@page_recording), headers: headers
    assert_response :not_found
    assert_empty @calls

    @page_recording.update_column(:trashed_at, nil)
    post restore_path(@page_recording), headers: headers
    assert_response :success
    assert_equal @page_recording.id, JSON.parse(response.body).fetch("recording_id")
  end

  test "a role resolver that returns view does not run a declared restore on a trashed recording" do
    @page_recording.update_column(:trashed_at, Time.current)
    register_restore_action
    seen_recordings = []
    RecordingStudioApi.configuration.capability_action_role_resolver = lambda do |recording:, **|
      seen_recordings << recording
      :view
    end

    post restore_path(@page_recording), headers: headers
    assert_response :not_found
    assert_empty @calls
    assert_equal [@page_recording.id], seen_recordings.map(&:id)

    @page_recording.update_column(:trashed_at, nil)
    post restore_path(@page_recording), headers: headers
    assert_response :success
    assert_equal @page_recording.id, JSON.parse(response.body).fetch("recording_id")
  end

  test "a declared destroy action with an admin role resolves a trashed recording" do
    @page_recording.update_column(:trashed_at, Time.current)
    enable_echo
    RecordingStudioApi.register_capability_action(
      :trashable_purge,
      capability: :echoable,
      http_verb: :post,
      required_role: :admin,
      include_trashed: true,
      trashed_semantics: :destroy,
      handler: ->(context) { { recording_id: context.recording&.id } },
      serializer: ->(result) { result }
    )
    RecordingStudioApi.register_recordable_type_api("Page", capability_actions: %i[trashable_purge])

    post purge_path(@page_recording), headers: headers
    assert_response :forbidden

    admin_headers, admin_page = admin_client
    admin_page.update_column(:trashed_at, Time.current)
    post purge_path(admin_page), headers: admin_headers
    assert_response :success
    assert_equal admin_page.id, JSON.parse(response.body).fetch("recording_id")
  end

  test "a nested handler authorizes the relationship before it runs" do
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
          endpoints: %i[show],
          authorize: ->(_context) { false }
        }
      }
    )
    RecordingStudioApi.register_resource_handler("Folder", :show, handler: probe("nested-show"))

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders/#{@folder_recording.id}", headers: headers
    assert_response :forbidden
    assert_equal "Not authorized to read relationship folders", JSON.parse(response.body).dig("error", "message")
    assert_empty @calls
  end

  private

  def headers
    { "Authorization" => "Bearer #{@access_token}" }
  end

  def owned_write(name)
    lambda do |context|
      recording = owned_recording!(context)
      context.access_grant.authorize!(recording: recording, role: :edit)
      @calls << {
        name: name,
        id: context.id,
        recording_id: recording.id
      }
      { json: { handled: name, recording_id: recording.id }, status: :ok }
    end
  end

  def owned_capability_write(name)
    lambda do |context|
      recording = owned_recording!(context)
      context.access_grant.authorize!(recording: recording, role: :edit)
      @calls << { name: name, recording_id: recording.id, id: context.id }
      { recording_id: recording.id }
    end
  end

  def owned_endpoint_write(name)
    lambda do |context|
      recording = owned_recording!(context)
      context.access_grant.authorize!(recording: recording, role: :edit)
      @calls << { name: name, recording_id: recording.id, params_id: context.params[:id] }
      { handled: name, recording_id: recording.id }
    end
  end

  def owned_recording!(context)
    id = member_id_for(context)
    raise RecordingStudioApi::NotFoundError, api_scope_missing_message("Page") if id.blank?

    type = context.respond_to?(:recordable_type) && context.recordable_type.present? ? context.recordable_type.to_s : "Page"
    recording = RecordingStudio::Recording.unscoped.find_by(id: id)
    recording ||= RecordingStudio::Recording.unscoped.find_by(recordable_type: type, recordable_id: id)
    missing = api_scope_missing_message("Page")
    raise RecordingStudioApi::NotFoundError, missing if recording.nil? || recording.recordable_type != type

    owner = context.access_grant.owner
    visible = owner.present? && RecordingStudioAccessible.authorized?(actor: owner, recording: recording, role: :view)
    raise RecordingStudioApi::NotFoundError, missing unless visible

    recording
  end

  def member_id_for(context)
    return context.id if context.respond_to?(:id) && context.id.present?
    return unless context.respond_to?(:params)

    context.params[:id].presence || context.params["id"]
  end

  def probe(name)
    lambda do |context|
      @calls << {
        name: name,
        id: context.respond_to?(:id) ? context.id : nil,
        parent_id: context.respond_to?(:parent_id) ? context.parent_id : nil,
        recording_id: context.recording&.id,
        parent_recording_id: context.respond_to?(:parent_recording) ? context.parent_recording&.id : nil,
        params_parent_id: context.params[:parent_id]
      }
      { json: { handled: name }, status: name == "create" ? :created : :ok }
    end
  end

  def endpoint_probe(name)
    lambda do |context|
      @calls << {
        name: name,
        recording_id: context.recording&.id,
        params_id: context.params[:id]
      }
      { handled: name, recording_id: context.recording&.id }
    end
  end

  def register_page_show
    RecordingStudioApi.register_resource_handler("Page", :show, handler: probe("show"))
  end

  def register_member_echo
    enable_echo
    RecordingStudioApi.register_recordable_type_api("Page", capability_actions: %i[echo])
    RecordingStudioApi.register_resource_handler("Page", :echo, handler: probe("echo"))
  end

  def enable_echo
    RecordingStudio.enable_capability(:echoable, on: "Page")
    RecordingStudioApi.register_capability_action(
      :echo,
      capability: :echoable,
      http_verb: :post,
      handler: ->(_context) { {} }
    )
  end

  def register_nested_folders
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
    RecordingStudioApi.register_resource_handler("Folder", :show, handler: probe("nested-show"))
  end

  def register_unscoped_role_endpoints
    RecordingStudioApi.register_endpoint(:list_notes, http_verb: :get, path: "notes", handler: endpoint_probe("list"))
    RecordingStudioApi.register_endpoint(:create_note, http_verb: :post, path: "notes", handler: endpoint_probe("create"))
    RecordingStudioApi.register_endpoint(:revise_note, http_verb: :patch, path: "notes", handler: endpoint_probe("revise"))
    RecordingStudioApi.register_endpoint(
      :remove_person,
      http_verb: :delete,
      path: "people/:id",
      scope_id: false,
      required_role: :edit,
      handler: endpoint_probe("remove")
    )
    RecordingStudioApi.register_endpoint(
      :mark_read,
      http_verb: :post,
      path: "notifications/:id/mark-read",
      scope_id: false,
      required_role: :view,
      handler: endpoint_probe("mark_read")
    )
  end

  def register_scoped_endpoint
    RecordingStudioApi.register_endpoint(
      :scoped_page,
      http_verb: :get,
      path: "scoped-pages/:id",
      recordable_type: "Page",
      handler: endpoint_probe("endpoint")
    )
  end

  def view_client
    role_client(:view, "View scope token")
  end

  def admin_client
    role_client(:admin, "Admin scope token")
  end

  def role_client(role, token_name)
    user = create_user
    root, access = create_access_recording_for(user: user, role: role)
    page = create_page_recording(root_recording: root)
    token = issue_oauth_access_token_for(access_recording: access, name: token_name)
    [{ "Authorization" => "Bearer #{token}" }, page]
  end

  def register_restore_action
    enable_echo
    register_capability_action(
      :trashable_restore,
      include_trashed: true,
      trashed_semantics: :restore,
      handler: lambda { |context|
        @calls << { name: "restore", recording_id: context.recording&.id }
        { recording_id: context.recording&.id }
      }
    )
    RecordingStudioApi.register_recordable_type_api("Page", capability_actions: %i[trashable_restore])
  end

  def register_capability_action(name, **)
    RecordingStudioApi.register_capability_action(
      name,
      capability: :echoable,
      http_verb: :post,
      handler: ->(_context) { {} },
      serializer: ->(result) { result },
      **
    )
  end

  def restore_path(recording)
    "/recording_studio_api/api/v1/pages/#{recording.id}/actions/trashable_restore"
  end

  def purge_path(recording)
    "/recording_studio_api/api/v1/pages/#{recording.id}/actions/trashable_purge"
  end
end
