# frozen_string_literal: true

require_relative "../../../support/api_dummy_helpers"

class ApiV1MemberActionsControllerTest < ActionDispatch::IntegrationTest
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user)
    @page_recording = create_page_recording(root_recording: @root_recording)
    @access_token = issue_oauth_access_token_for(access_recording: @access_recording, name: "Integration token")

    RecordingStudio.enable_capability(:echoable, on: "Page")
    RecordingStudioApi.register_capability_action(
      :echo,
      capability: :echoable,
      http_verb: :post,
      handler: lambda { |context|
        {
          recording: context.recording,
          progress_reporter: context.progress_reporter,
          cancelled: context.cancelled?,
          progress_result: context.progress(current: 1, message: "echo")
        }
      },
      serializer: lambda { |result|
        {
          id: result.fetch(:recording).id,
          progress_reporter_nil: result.fetch(:progress_reporter).nil?,
          cancelled: result.fetch(:cancelled),
          progress_result: result.fetch(:progress_result)
        }
      }
    )
    RecordingStudioApi.register_recordable_type_api(
      "Page",
      capability_actions: %i[echo echo_access_grant echo_params versioned_echo peek]
    )
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "executes a capability action for types that declare the capability without listing it" do
    RecordingStudioApi.register_capability_action(
      :shout,
      capability: :echoable,
      http_verb: :post,
      handler: ->(context) { context.recording }
    )

    post "/recording_studio_api/api/v1/pages/#{@page_recording.id}/actions/shout",
         headers: authorization_headers

    assert_response :success
    assert_equal @page_recording.id, JSON.parse(response.body).fetch("id")
  end

  test "rejects an auto capability action when the type opts out of auto enablement" do
    RecordingStudioApi.register_capability_action(
      :shout,
      capability: :echoable,
      http_verb: :post,
      handler: ->(context) { context.recording }
    )
    RecordingStudioApi.register_recordable_type_api("Page", auto_capability_actions: false)

    post "/recording_studio_api/api/v1/pages/#{@page_recording.id}/actions/shout",
         headers: authorization_headers

    assert_response :unprocessable_entity
    assert_equal "shout is not enabled for Page", JSON.parse(response.body).dig("error", "message")
  end

  test "rejects a capability action when the type does not declare the capability" do
    folder_recording = @page_recording.parent_recording

    RecordingStudio.enable_capability(:movable, on: "Folder")
    RecordingStudioApi.configuration.action_registry.instance_variable_get(:@registrations).delete("move")
    RecordingStudioApi.register_capability_action(
      :move,
      capability: :movable,
      http_verb: :post,
      handler: ->(context) { context.recording }
    )
    RecordingStudioApi.register_recordable_type_api("Folder", capability_actions: %i[move])

    post "/recording_studio_api/api/v1/folders/#{folder_recording.id}/actions/move",
        headers: authorization_headers

    assert_response :success
    assert_equal folder_recording.id, JSON.parse(response.body).fetch("id")

    post "/recording_studio_api/api/v1/pages/#{@page_recording.id}/actions/move",
        headers: authorization_headers

    assert_response :unprocessable_entity
    assert_equal "move is not enabled for Page", JSON.parse(response.body).dig("error", "message")
  end

  test "denies an auto-enabled capability action below the required role" do
    RecordingStudioApi.register_capability_action(
      :shout,
      capability: :echoable,
      http_verb: :post,
      required_role: :edit,
      handler: ->(context) { context.recording }
    )
    view_user = create_user(email: "view-only-auto-enabled-actions@example.com")
    view_root_recording, view_access_recording = create_access_recording_for(user: view_user, role: :view)
    view_page_recording = create_page_recording(root_recording: view_root_recording)
    view_token = issue_oauth_access_token_for(access_recording: view_access_recording, name: "View-only auto-enable token")

    post "/recording_studio_api/api/v1/pages/#{view_page_recording.id}/actions/shout",
         headers: { "Authorization" => "Bearer #{view_token}" }

    assert_response :forbidden
    assert_equal unauthorized_role_message(:edit), JSON.parse(response.body).dig("error", "message")
  end

  test "dispatches a registered capability action with OAuth2 bearer authentication" do
    post "/recording_studio_api/api/v1/pages/#{@page_recording.id}/actions/echo",
         headers: authorization_headers

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal @page_recording.id, payload.fetch("id")
    assert_equal true, payload.fetch("progress_reporter_nil")
    assert_equal false, payload.fetch("cancelled")
    assert_nil payload.fetch("progress_result")
  end

  test "dispatches a registered capability action through the nested child route" do
    post "/recording_studio_api/api/v1/pages/#{@page_recording.id}/echo",
         headers: authorization_headers

    assert_response :success
    assert_equal @page_recording.id, JSON.parse(response.body).fetch("id")
  end

  test "dispatches a get member capability action on the actions route and short alias" do
    RecordingStudioApi.register_capability_action(
      :peek,
      capability: :echoable,
      http_verb: :get,
      required_role: :view,
      handler: ->(context) { { peeked_id: context.recording.id } },
      serializer: ->(result) { result }
    )

    get "/recording_studio_api/api/v1/pages/#{@page_recording.id}/actions/peek",
        headers: authorization_headers

    assert_response :success
    assert_equal @page_recording.id, JSON.parse(response.body).fetch("peeked_id")

    get "/recording_studio_api/api/v1/pages/#{@page_recording.id}/peek",
        headers: authorization_headers

    assert_response :success
    assert_equal @page_recording.id, JSON.parse(response.body).fetch("peeked_id")
  end

  test "rejects get against a post-only member capability action" do
    get "/recording_studio_api/api/v1/pages/#{@page_recording.id}/actions/echo",
        headers: authorization_headers

    assert_response :unprocessable_entity
    assert_equal "echo must be called with POST", JSON.parse(response.body).dig("error", "message")
  end

  test "dispatches a get member capability action on a named api" do
    RecordingStudioApi.configuration.api(:operations) { |api| api.default_access = :read_only }
    RecordingStudioApi.register_recordable_type_api("Workspace", api: :operations)
    RecordingStudioApi.register_capability_action(
      :peek,
      capability: :echoable,
      http_verb: :get,
      required_role: :view,
      handler: ->(context) { { peeked_id: context.recording.id } },
      serializer: ->(result) { result },
      api: :operations
    )
    RecordingStudioApi.register_recordable_type_api(
      "Page",
      api: :operations,
      capability_actions: %i[peek]
    )

    operations_token = issue_named_api_token(api: :operations, name: "Operations peek token")

    get "/recording_studio_api/apis/operations/v1/pages/#{@page_recording.id}/actions/peek",
        headers: { "Authorization" => "Bearer #{operations_token}" }

    assert_response :success
    assert_equal @page_recording.id, JSON.parse(response.body).fetch("peeked_id")
  end

  test "dispatches the contribution version selected by the request api version" do
    RecordingStudioApi.configuration.api_versions = %w[v1 v2]
    RecordingStudioApi.configuration.version("v1") { |api| api.use :echoable, "~> 1.0" }
    RecordingStudioApi.configuration.version("v2") { |api| api.use :echoable }

    RecordingStudioApi.register_capability_action(
      :versioned_echo,
      capability: :echoable,
      version: "1.5.0",
      http_verb: :post,
      handler: ->(_context) { { version: "legacy" } },
      serializer: ->(result) { result }
    )
    RecordingStudioApi.register_capability_action(
      :versioned_echo,
      capability: :echoable,
      version: "2.0.0",
      http_verb: :post,
      handler: ->(_context) { { version: "current" } },
      serializer: ->(result) { result }
    )

    post "/recording_studio_api/api/v1/pages/#{@page_recording.id}/actions/versioned_echo",
         headers: authorization_headers

    assert_response :success
    assert_equal "legacy", JSON.parse(response.body).fetch("version")
  end

  test "passes only action payload params to handlers" do
    RecordingStudioApi.register_capability_action(
      :echo_params,
      capability: :echoable,
      http_verb: :post,
      handler: ->(context) { context.params },
      serializer: ->(result) { result }
    )

    post "/recording_studio_api/api/v1/pages/#{@page_recording.id}/actions/echo_params",
         params: {
           custom_value: "safe",
           nested: { key: "value" },
           action_name: "override",
           id: "override-id",
           resource: "override-resource",
           controller: "override-controller"
         },
         headers: authorization_headers

    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal "safe", payload.fetch("custom_value")
    assert_equal({ "key" => "value" }, payload.fetch("nested"))
    refute_includes payload.keys, "action_name"
    refute_includes payload.keys, "id"
    refute_includes payload.keys, "resource"
    refute_includes payload.keys, "controller"
    refute_includes payload.keys, "action"
    refute_includes payload.keys, "format"
  end

  test "passes authenticated access grant to capability handlers" do
    RecordingStudioApi.register_capability_action(
      :echo_access_grant,
      capability: :echoable,
      http_verb: :post,
      handler: lambda { |context|
        {
          access_recording_id: context.access_recording.id,
          access_grant_recording_id: context.access_grant.access_recording.id,
          actor_id: context.access_grant.actor.id
        }
      },
      serializer: ->(result) { result }
    )

    post "/recording_studio_api/api/v1/pages/#{@page_recording.id}/actions/echo_access_grant",
         headers: authorization_headers

    assert_response :success

    payload = JSON.parse(response.body)
    api_client = RecordingStudioApi::ApiClient.find_by!(name: "Integration token")
    assert_equal api_client.access_recording.id, payload.fetch("access_recording_id")
    assert_equal api_client.access_recording.id, payload.fetch("access_grant_recording_id")
    assert_equal api_client.id, payload.fetch("actor_id")
  end

  test "scopes capability action execution to the authenticated root recording" do
    root_recording, access_recording = create_access_recording_for(user: @user)
    in_scope_page = create_page_recording(root_recording: root_recording)
    other_root_recording, = create_access_recording_for(user: create_user(email: "other-root-actions@example.com"))
    out_of_scope_page = create_page_recording(root_recording: other_root_recording)
    scoped_oauth_token = issue_oauth_access_token_for(access_recording: access_recording, name: "Scoped token")

    post "/recording_studio_api/api/v1/pages/#{in_scope_page.id}/actions/echo",
        headers: { "Authorization" => "Bearer #{scoped_oauth_token}" }

    assert_response :success

    post "/recording_studio_api/api/v1/pages/#{out_of_scope_page.id}/actions/echo",
      headers: { "Authorization" => "Bearer #{scoped_oauth_token}" }

    assert_response :not_found
  end

  test "rejects a capability action for a resource outside the authenticated root scope" do
    _restricted_root_recording, restricted_access_recording = create_access_recording_for(
      user: create_user(email: "restricted-member-actions@example.com"),
      role: :edit
    )
    other_root_recording, = create_access_recording_for(user: create_user(email: "outside-member-actions@example.com"))
    hidden_page = create_page_recording(root_recording: other_root_recording)
    restricted_oauth_token = issue_oauth_access_token_for(access_recording: restricted_access_recording, name: "Restricted token")

    post "/recording_studio_api/api/v1/pages/#{hidden_page.id}/actions/echo",
         headers: { "Authorization" => "Bearer #{restricted_oauth_token}" }

    assert_response :not_found
    assert_equal api_scope_missing_message("Page"), JSON.parse(response.body).dig("error", "message")
  end

  test "rejects requests without a bearer token" do
    post "/recording_studio_api/api/v1/pages/#{@page_recording.id}/actions/echo"

    assert_response :unauthorized
  end

  test "denies a handler-backed member action below the required role" do
    view_user = create_user(email: "view-only-handler-member-actions@example.com")
    view_root_recording, view_access_recording = create_access_recording_for(user: view_user, role: :view)
    view_page_recording = create_page_recording(root_recording: view_root_recording)
    view_token = issue_oauth_access_token_for(access_recording: view_access_recording, name: "View-only handler token")
    RecordingStudioApi.register_resource_handler("Page", :echo, handler: lambda { |_context|
      { json: { handled: "echo" }, status: :ok }
    })

    post "/recording_studio_api/api/v1/pages/#{view_page_recording.id}/actions/echo",
         headers: { "Authorization" => "Bearer #{view_token}" }

    assert_response :forbidden
    assert_equal unauthorized_role_message(:edit), JSON.parse(response.body).dig("error", "message")
  end

  test "allows a handler-backed member action at the required role" do
    RecordingStudioApi.register_resource_handler("Page", :echo, handler: lambda { |_context|
      { json: { handled: "echo" }, status: :ok }
    })

    post "/recording_studio_api/api/v1/pages/#{@page_recording.id}/actions/echo",
         headers: authorization_headers

    assert_response :success
    assert_equal "echo", JSON.parse(response.body).fetch("handled")
  end

  test "denies custom member actions for clients below the default edit role" do
    view_user = create_user(email: "view-only-member-actions@example.com")
    view_root_recording, view_access_recording = create_access_recording_for(user: view_user, role: :view)
    view_page_recording = create_page_recording(root_recording: view_root_recording)
    view_token = issue_oauth_access_token_for(access_recording: view_access_recording, name: "View-only token")

    post "/recording_studio_api/api/v1/pages/#{view_page_recording.id}/actions/echo",
         headers: { "Authorization" => "Bearer #{view_token}" }

    assert_response :forbidden
    assert_equal unauthorized_role_message(:edit), JSON.parse(response.body).dig("error", "message")
  end

  test "allows the host to lower a custom action role requirement" do
    RecordingStudioApi.configuration.capability_action_roles = { echo: :view }
    view_user = create_user(email: "view-role-override-member-actions@example.com")
    view_root_recording, view_access_recording = create_access_recording_for(user: view_user, role: :view)
    view_page_recording = create_page_recording(root_recording: view_root_recording)
    view_token = issue_oauth_access_token_for(access_recording: view_access_recording, name: "View role override token")

    post "/recording_studio_api/api/v1/pages/#{view_page_recording.id}/actions/echo",
         headers: { "Authorization" => "Bearer #{view_token}" }

    assert_response :success
    assert_equal view_page_recording.id, JSON.parse(response.body).fetch("id")
  end

  test "a view token gets forbidden for invalid input and the contract does not run" do
    each_titled_action do |name, resource_handler|
      contract, ran = register_titled_action(name, resource_handler: resource_handler)
      token, page = access_for(:view, "view-invalid-#{name}")

      post member_action_path(page, name), params: { title: "" }, as: :json, headers: bearer(token)

      assert_response :forbidden, name
      body = JSON.parse(response.body)
      assert_equal "forbidden", body.dig("error", "code"), name
      assert_equal unauthorized_role_message(:edit), body.dig("error", "message"), name
      assert_nil body.dig("error", "details"), name
      assert_equal 0, contract.calls, name
      assert_empty ran, name
    end
  end

  test "an edit token gets invalid input when the contract rejects the body" do
    each_titled_action do |name, resource_handler|
      contract, ran = register_titled_action(name, resource_handler: resource_handler)
      token, page = access_for(:edit, "edit-invalid-#{name}")

      post member_action_path(page, name), params: { title: "" }, as: :json, headers: bearer(token)

      assert_response :unprocessable_entity, name
      body = JSON.parse(response.body)
      assert_equal "invalid_input", body.dig("error", "code"), name
      assert_equal "Invalid input for action #{name}", body.dig("error", "message"), name
      assert_includes body.dig("error", "details"), "title cannot be blank", name
      assert_equal 1, contract.calls, name
      assert_empty ran, name
    end
  end

  test "an edit token with valid input runs the handler" do
    each_titled_action do |name, resource_handler|
      contract, ran = register_titled_action(name, resource_handler: resource_handler)
      token, page = access_for(:edit, "edit-valid-#{name}")

      post member_action_path(page, name), params: { title: "Hello" }, as: :json, headers: bearer(token)

      assert_response :success, name
      assert_equal "Hello", JSON.parse(response.body).fetch("title"), name
      assert_equal page.id, JSON.parse(response.body).fetch("id"), name
      assert_equal 1, contract.calls, name
      assert_equal ["Hello"], ran, name
    end
  end

  test "a disabled action is rejected before the contract runs" do
    each_titled_action do |name, resource_handler|
      contract, ran = register_titled_action(name, resource_handler: resource_handler, enabled: false)
      view_token, view_page = access_for(:view, "view-disabled-#{name}")
      edit_token, edit_page = access_for(:edit, "edit-disabled-#{name}")
      hidden = create_page_recording(root_recording: create_access_recording_for(user: create_user).first)

      post member_action_path(view_page, name), params: { title: "" }, as: :json, headers: bearer(view_token)

      assert_response :forbidden, name
      forbidden = JSON.parse(response.body)
      assert_equal "forbidden", forbidden.dig("error", "code"), name
      assert_equal unauthorized_role_message(:edit), forbidden.dig("error", "message"), name
      assert_nil forbidden.dig("error", "details"), name
      refute_includes response.body, "not enabled", name
      refute_includes response.body, "cannot be blank", name

      post member_action_path(hidden, name), params: { title: "" }, as: :json, headers: bearer(edit_token)

      assert_response :not_found, name
      missing = JSON.parse(response.body)
      assert_equal "not_found", missing.dig("error", "code"), name
      assert_equal api_scope_missing_message("Page"), missing.dig("error", "message"), name
      refute_includes response.body, "not enabled", name
      refute_includes response.body, name.to_s, name

      post member_action_path(edit_page, name), params: { title: "" }, as: :json, headers: bearer(edit_token)

      assert_response :unprocessable_entity, name
      disabled = JSON.parse(response.body)
      assert_equal "unsupported_action", disabled.dig("error", "code"), name
      assert_equal "#{name} is not enabled for Page", disabled.dig("error", "message"), name
      assert_nil disabled.dig("error", "details"), name
      refute_includes response.body, "cannot be blank", name
      assert_equal 0, contract.calls, name
      assert_empty ran, name
    end
  end

  test "uses a host action role resolver" do
    edit_user = create_user(email: "resolver-member-actions@example.com")
    edit_root_recording, edit_access_recording = create_access_recording_for(user: edit_user, role: :edit)
    edit_page_recording = create_page_recording(root_recording: edit_root_recording)
    edit_token = issue_oauth_access_token_for(access_recording: edit_access_recording, name: "Resolver token")
    RecordingStudioApi.configuration.capability_action_role_resolver = lambda do |action:, recording:, **|
      action.name == "echo" && recording.id == edit_page_recording.id ? :admin : :edit
    end

    post "/recording_studio_api/api/v1/pages/#{edit_page_recording.id}/actions/echo",
         headers: { "Authorization" => "Bearer #{edit_token}" }

    assert_response :forbidden
  end

  test "a creates action replays one record for the same key and stores another record for a new key" do
    register_mint_action(creates: true)
    folder = @page_recording.parent_recording
    other_folder = RecordingStudio::Recording.create!(
      recordable: Folder.create!(name: "Other mint parent"),
      parent_recording: @root_recording
    )
    key = "mint-#{SecureRandom.hex(4)}"

    with_idempotency_cache do
      assert_difference("Folder.count", 1) do
        post mint_path(folder), params: { name: "First mint" }, headers: idempotency_headers(key)
      end
      assert_response :success
      first = JSON.parse(response.body)
      assert_equal "First mint", first.fetch("name")
      assert_equal [key], @mint_keys

      assert_no_difference("Folder.count") do
        post mint_path(folder), params: { name: "First mint" }, headers: idempotency_headers(key)
      end
      assert_response :success
      second = JSON.parse(response.body)
      assert_equal first.fetch("id"), second.fetch("id")
      assert_equal "First mint", second.fetch("name")
      assert_equal [key], @mint_keys

      assert_difference("Folder.count", 1) do
        post mint_path(folder), params: { name: "Second mint" }, headers: idempotency_headers("#{key}-new")
      end
      assert_response :success
      third = JSON.parse(response.body)
      refute_equal first.fetch("id"), third.fetch("id")
      assert_equal "Second mint", third.fetch("name")

      assert_difference("Folder.count", 1) do
        post mint_path(other_folder), params: { name: "First mint" }, headers: idempotency_headers(key)
      end
      assert_response :success
      refute_equal first.fetch("id"), JSON.parse(response.body).fetch("id")
    end
  end

  test "a creates action refuses the same Idempotency-Key when the input changes" do
    register_mint_action(creates: true)
    folder = @page_recording.parent_recording
    key = "mint-mismatch-#{SecureRandom.hex(4)}"

    with_idempotency_cache do
      post mint_path(folder), params: { name: "Kept mint" }, headers: idempotency_headers(key)
      assert_response :success
      kept_id = JSON.parse(response.body).fetch("id")

      assert_no_difference("Folder.count") do
        post mint_path(folder), params: { name: "Changed mint" }, headers: idempotency_headers(key)
      end
      assert_response :unprocessable_entity
      payload = JSON.parse(response.body)
      assert_equal "idempotency_key_reused", payload.dig("error", "code")
      assert_equal "Idempotency key already used with different parameters", payload.dig("error", "message")
      assert_equal kept_id, RecordingStudio::Recording.find(kept_id).id
      assert_equal 1, @mint_keys.length
    end
  end

  test "an action without creates runs again for the same Idempotency-Key" do
    register_mint_action(creates: false)
    folder = @page_recording.parent_recording
    key = "mint-open-#{SecureRandom.hex(4)}"

    with_idempotency_cache do
      assert_difference("Folder.count", 2) do
        post mint_path(folder), params: { name: "Open mint" }, headers: idempotency_headers(key)
        assert_response :success
        first_id = JSON.parse(response.body).fetch("id")

        post mint_path(folder), params: { name: "Open mint again" }, headers: idempotency_headers(key)
        assert_response :success
        refute_equal first_id, JSON.parse(response.body).fetch("id")
      end
      assert_equal [key, key], @mint_keys
    end
  end

  test "a member resource handler with creates replays the Idempotency-Key" do
    register_mint_handler(creates: true)
    folder = @page_recording.parent_recording
    key = "mint-handler-#{SecureRandom.hex(4)}"

    with_idempotency_cache do
      assert_difference("Folder.count", 1) do
        post mint_path(folder), params: { name: "Handler mint" }, headers: idempotency_headers(key)
      end
      assert_response :created
      first_id = JSON.parse(response.body).fetch("id")

      assert_no_difference("Folder.count") do
        post mint_path(folder), params: { name: "Handler mint" }, headers: idempotency_headers(key)
      end
      assert_response :created
      assert_equal first_id, JSON.parse(response.body).fetch("id")
      assert_equal "Handler mint", JSON.parse(response.body).fetch("name")
      assert_equal [key], @mint_keys
    end
  end

  test "a member resource handler without creates runs again for the same Idempotency-Key" do
    register_mint_handler(creates: false)
    folder = @page_recording.parent_recording
    key = "mint-handler-open-#{SecureRandom.hex(4)}"

    with_idempotency_cache do
      assert_difference("Folder.count", 2) do
        post mint_path(folder), params: { name: "Handler open" }, headers: idempotency_headers(key)
        assert_response :created
        first_id = JSON.parse(response.body).fetch("id")

        post mint_path(folder), params: { name: "Handler open again" }, headers: idempotency_headers(key)
        assert_response :created
        refute_equal first_id, JSON.parse(response.body).fetch("id")
      end
      assert_equal [key, key], @mint_keys
    end
  end

  private

  def authorization_headers
    { "Authorization" => "Bearer #{@access_token}" }
  end

  def idempotency_headers(key)
    authorization_headers.merge("Idempotency-Key" => key)
  end

  def mint_path(folder)
    "/recording_studio_api/api/v1/folders/#{folder.id}/actions/mint"
  end

  def with_idempotency_cache(&)
    previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    RecordingStudioApi::IdempotencyStore.stub(:redis, nil, &)
  ensure
    Rails.cache = previous_cache
  end

  def register_mint_action(creates:)
    RecordingStudio.enable_capability(:echoable, on: "Folder")
    @mint_keys = []
    keys = @mint_keys
    RecordingStudioApi.register_capability_action(
      :mint,
      capability: :echoable,
      http_verb: :post,
      creates: creates,
      handler: lambda do |context|
        keys << context.idempotency_key
        folder = Folder.create!(name: context.params[:name].to_s)
        RecordingStudio::Recording.create!(recordable: folder, parent_recording: context.recording)
      end
    )
  end

  def register_mint_handler(creates:)
    RecordingStudio.enable_capability(:echoable, on: "Folder")
    @mint_keys = []
    keys = @mint_keys
    RecordingStudioApi.register_capability_action(
      :mint,
      capability: :echoable,
      http_verb: :post,
      handler: ->(*) { raise "capability handler should not run" }
    )
    RecordingStudioApi.register_resource_handler(
      "Folder",
      :mint,
      creates: creates,
      handler: lambda do |context|
        keys << context.idempotency_key
        folder = Folder.create!(name: context.params[:name].to_s)
        recording = RecordingStudio::Recording.create!(recordable: folder, parent_recording: context.recording)
        { json: { id: recording.id, name: folder.name }, status: :created }
      end
    )
  end

  def bearer(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def member_action_path(page, action_name)
    "/recording_studio_api/api/v1/pages/#{page.id}/actions/#{action_name}"
  end

  def each_titled_action
    yield :rename, false
    yield :handled_rename, true
  end

  def access_for(role, name)
    root, access = create_access_recording_for(user: create_user, role: role)
    page = create_page_recording(root_recording: root)
    token = issue_oauth_access_token_for(access_recording: access, name: name)
    [token, page]
  end

  def register_titled_action(name, resource_handler:, enabled: true)
    contract = CountingInputContract.new
    ran = []
    RecordingStudioApi.register_capability_action(
      name,
      capability: :echoable,
      http_verb: :post,
      required_role: :edit,
      input_contract: contract,
      handler: lambda { |context|
        ran << context.params[:title]
        { id: context.recording.id, title: context.params[:title] }
      },
      serializer: ->(result) { result }
    )
    if resource_handler
      RecordingStudioApi.register_resource_handler("Page", name, handler: lambda { |context|
        ran << context.params[:title]
        { json: { id: context.recording.id, title: context.params[:title] }, status: :ok }
      })
    end
    RecordingStudioApi.register_recordable_type_api("Page", auto_capability_actions: false) unless enabled
    [contract, ran]
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

class CountingInputContract < RecordingStudioApi::ActionInputContract
  attr_reader :calls

  def initialize
    super(fields: { title: { type: :string, required: true, allow_blank: false } })
    @calls = 0
  end

  def call(raw_params)
    @calls += 1
    super
  end
end

