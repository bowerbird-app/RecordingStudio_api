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
    assert_equal "Resource was not found in this API scope", JSON.parse(response.body).dig("error", "message")

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
    assert_equal "Resource type does not match Page", JSON.parse(response.body).dig("error", "message")

    get "/recording_studio_api/api/v1/scoped-pages/#{@folder_recording.id}", headers: headers
    assert_response :not_found
    assert_equal "Resource type does not match Page", JSON.parse(response.body).dig("error", "message")
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
    assert_equal "API access grant is not authorized for this capability", JSON.parse(response.body).dig("error", "message")
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

  test "owns_scoping on a read action runs for another root and a write action is rejected" do
    RecordingStudioApi.register_resource_handler("Page", :show, owns_scoping: true, handler: probe("show"))
    enable_echo
    RecordingStudioApi.register_capability_action(
      :published,
      capability: :echoable,
      http_verb: :get,
      required_role: :view,
      owns_scoping: true,
      handler: ->(context) { { recording_id: context.recording&.id, id: context.id } },
      serializer: ->(result) { result }
    )
    RecordingStudioApi.register_recordable_type_api("Page", capability_actions: %i[published])
    RecordingStudioApi.register_endpoint(
      :public_page,
      http_verb: :get,
      path: "public-pages/:id",
      recordable_type: "Page",
      owns_scoping: true,
      handler: endpoint_probe("public")
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

    page_update = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.register_resource_handler("Page", :update, owns_scoping: true, handler: probe("update"))
    end
    echo_write = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.register_capability_action(
        :echo,
        capability: :echoable,
        http_verb: :post,
        owns_scoping: true,
        handler: ->(_context) { {} }
      )
    end
    endpoint_write = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.register_endpoint(
        :write_public,
        http_verb: :post,
        path: "public-pages",
        owns_scoping: true,
        handler: ->(_context) { {} }
      )
    end
    assert_includes page_update.message, "owns_scoping is only allowed on a read action"
    assert_includes echo_write.message, "owns_scoping is only allowed on a read action"
    assert_includes endpoint_write.message, "owns_scoping is only allowed on a read action"
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

  private

  def headers
    { "Authorization" => "Bearer #{@access_token}" }
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
    view_user = create_user
    view_root, view_access = create_access_recording_for(user: view_user, role: :view)
    view_page = create_page_recording(root_recording: view_root)
    token = issue_oauth_access_token_for(access_recording: view_access, name: "View scope token")
    [{ "Authorization" => "Bearer #{token}" }, view_page]
  end
end
