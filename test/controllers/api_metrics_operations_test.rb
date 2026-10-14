# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"

class ApiMetricsOperationsTest < ActionDispatch::IntegrationTest
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    configure_dummy_operations_api!
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      api: :operations,
      operations: %i[index show],
      serializer: ->(recordable, **) { { name: recordable.name } },
      output_keys: %i[name]
    )
    RecordingStudioApi.register_default_resource_actions!
    RecordingStudioMetrics.registry.reset!
    RecordingStudioApi::Metrics.register!
    RecordingStudioMetrics::Api.register!(api: :operations)

    @manager = create_user
    _admin_root, @admin_recording = create_admin_root_recording(name: "Admin")
    create_access_recording(parent_recording: @admin_recording, user: @manager, role: :admin)
    RecordingStudioApi::Admin::ApiAuthorization.recording_for(
      api: :operations,
      root_recording: @admin_recording,
      create: true
    )

    seed_daily_metrics!
    seed_keys!

    @authorized_token = issue_operations_token(@manager, @admin_recording)
    @unauthorized_token = issue_unauthorized_operations_token
    @public_token = issue_oauth_access_token_for(
      access_recording: create_access_recording_for(user: create_user).last
    )
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "operations metrics index lists registered metrics for an authorized management token" do
    get "#{operations_root}/metrics", headers: bearer_headers(@authorized_token)

    assert_response :success
    identifiers = JSON.parse(response.body).fetch("metrics").map { |row| row.fetch("identifier") }
    assert_includes identifiers, "api_requests.over_time"
    assert_includes identifiers, "api_requests.errors_over_time"
    assert_includes identifiers, "api_requests.by_status_class"
    assert_includes identifiers, "api_requests.rate_limited"
    assert_includes identifiers, "api_keys.active"
  end

  test "authorized management operations token reads seeded metric values" do
    get "#{operations_root}/metrics/api_requests/rate_limited", headers: bearer_headers(@authorized_token)
    assert_response :success
    assert_equal 4, JSON.parse(response.body).fetch("value")

    get "#{operations_root}/metrics/api_keys/active", headers: bearer_headers(@authorized_token)
    assert_response :success
    assert_equal RecordingStudioApi::ApiCredential.active.count, JSON.parse(response.body).fetch("value")

    get "#{operations_root}/metrics/api_requests/by_status_class", headers: bearer_headers(@authorized_token)
    assert_response :success
    by_class = JSON.parse(response.body).fetch("data").to_h { |row| [row.fetch("key").to_i, row.fetch("value")] }
    assert_equal 15, by_class[2]
    assert_equal 3, by_class[4]
    assert_equal 1, by_class[5]
  end

  test "unauthorized operations token and public token are denied" do
    get "#{operations_root}/metrics", headers: bearer_headers(@unauthorized_token)
    assert_response :success
    assert_equal({ "metrics" => [] }, JSON.parse(response.body))

    get "#{operations_root}/api_keys/metrics", headers: bearer_headers(@unauthorized_token)
    assert_response :success
    assert_equal({ "metrics" => [] }, JSON.parse(response.body))

    get "#{operations_root}/metrics/api_keys/active", headers: bearer_headers(@unauthorized_token)
    assert_response :forbidden

    get "#{operations_root}/api_keys/metrics/active", headers: bearer_headers(@unauthorized_token)
    assert_response :forbidden

    get "#{operations_root}/metrics", headers: bearer_headers(@public_token)
    assert_response :unauthorized

    get "#{operations_root}/api_keys/metrics", headers: bearer_headers(@public_token)
    assert_response :unauthorized

    get "#{operations_root}/api_keys/metrics/active", headers: bearer_headers(@public_token)
    assert_response :unauthorized
  end

  test "from and to match start and end, including each alias alone" do
    window = { interval: "day", start: "2026-04-01T00:00:00Z", end: "2026-04-03T00:00:00Z" }
    aliases = { interval: "day", from: "2026-04-01T00:00:00Z", to: "2026-04-03T00:00:00Z" }

    travel_to Time.utc(2026, 6, 1, 12, 0, 0) do
      get "#{operations_root}/metrics/api_requests/over_time", params: window, headers: bearer_headers(@authorized_token)
      assert_response :success
      canonical = response.body
      payload = JSON.parse(canonical)
      assert_equal(
        {
          "start" => "2026-04-01T00:00:00Z",
          "end" => "2026-04-03T00:00:00Z",
          "boundary" => "start_inclusive_end_exclusive"
        },
        payload.fetch("period")
      )
      values = payload.fetch("data").to_h { |row| [row.fetch("date"), row.fetch("value")] }
      assert_equal 12, values.fetch("2026-04-01")
      assert_equal 7, values.fetch("2026-04-02")

      get "#{operations_root}/metrics/api_requests/over_time", params: aliases, headers: bearer_headers(@authorized_token)
      assert_equal canonical, response.body
    end

    travel_to Time.utc(2026, 6, 1, 12, 0, 0) do
      get "#{operations_root}/metrics/api_requests/over_time",
          params: { from: "2026-04-01T00:00:00Z", interval: "day" },
          headers: bearer_headers(@authorized_token)
      assert_response :success
      from_alone = response.body
      assert_equal "2026-04-01T00:00:00Z", JSON.parse(from_alone).fetch("period").fetch("start")

      get "#{operations_root}/metrics/api_requests/over_time",
          params: { start: "2026-04-01T00:00:00Z", interval: "day" },
          headers: bearer_headers(@authorized_token)
      assert_equal from_alone, response.body

      get "#{operations_root}/metrics/api_requests/over_time",
          params: { to: "2026-04-03T00:00:00Z", interval: "day" },
          headers: bearer_headers(@authorized_token)
      assert_response :unprocessable_entity
      assert_equal(
        { "error" => { "code" => "invalid_input", "message" => "end_at must be after start_at" } },
        JSON.parse(response.body)
      )
      to_alone = response.body

      get "#{operations_root}/metrics/api_requests/over_time",
          params: { end: "2026-04-03T00:00:00Z", interval: "day" },
          headers: bearer_headers(@authorized_token)
      assert_equal to_alone, response.body
    end
  end

  test "start beats from and start_at beats from" do
    headers = bearer_headers(@authorized_token)
    path = "#{operations_root}/metrics/api_requests/over_time"

    get path, params: {
      start: "2026-04-01T00:00:00Z",
      from: "2026-04-02T00:00:00Z",
      end: "2026-04-03T00:00:00Z",
      interval: "day"
    }, headers: headers
    assert_response :success
    assert_equal "2026-04-01T00:00:00Z", JSON.parse(response.body).fetch("period").fetch("start")

    get path, params: {
      start_at: "2026-04-01T00:00:00Z",
      from: "2026-04-02T00:00:00Z",
      end: "2026-04-03T00:00:00Z",
      interval: "day"
    }, headers: headers
    assert_response :success
    assert_equal "2026-04-01T00:00:00Z", JSON.parse(response.body).fetch("period").fetch("start")
  end

  test "group_by is ignored and does not reach execute" do
    path = "#{operations_root}/metrics/api_requests/over_time"
    headers = bearer_headers(@authorized_token)
    window = { start: "2026-04-01T00:00:00Z", end: "2026-04-03T00:00:00Z", interval: "day" }

    travel_to Time.utc(2026, 6, 1, 12, 0, 0) do
      get path, params: window, headers: headers
      assert_response :success
      without_group = response.body

      get path, params: window.merge(group_by: "status_class"), headers: headers
      assert_response :success
      assert_equal without_group, response.body
    end

    calls = []
    original = RecordingStudioMetrics.method(:execute)
    RecordingStudioMetrics.stub(:execute, lambda { |identifier, **kwargs|
      calls << [identifier, kwargs]
      original.call(identifier, **kwargs)
    }) do
      get path, params: {
        from: "2026-04-01T00:00:00Z",
        to: "2026-04-03T00:00:00Z",
        interval: "day",
        group_by: "status_class"
      }, headers: headers
    end

    assert_response :success
    identifier, kwargs = calls.fetch(0)
    assert_equal "api_requests.over_time", identifier
    assert_equal %i[context interval start_at end_at filters], kwargs.keys
    assert_equal "2026-04-01T00:00:00Z", kwargs.fetch(:start_at)
    assert_equal "2026-04-03T00:00:00Z", kwargs.fetch(:end_at)
    assert_equal({}, kwargs.fetch(:filters))
  end

  test "undeclared metric filters are rejected" do
    get "#{operations_root}/metrics/api_requests/over_time",
        params: { filters: { x: "1" }, interval: "day" },
        headers: bearer_headers(@authorized_token)

    assert_response :unprocessable_entity
    assert_equal(
      { "error" => { "code" => "invalid_input", "message" => "Unknown filters: x" } },
      JSON.parse(response.body)
    )
  end

  test "resource filter on the catalog matches the resource-first path" do
    headers = bearer_headers(@authorized_token)

    get "#{operations_root}/metrics", params: { resource: "api_requests" }, headers: headers
    assert_response :success
    requests_body = response.body
    assert_equal(
      %w[api_requests.by_status_class api_requests.errors_over_time api_requests.over_time api_requests.rate_limited],
      JSON.parse(requests_body).fetch("metrics").map { |row| row.fetch("identifier") }.sort
    )
    refute_includes JSON.parse(requests_body).fetch("metrics").map { |row| row.fetch("identifier") }, "api_keys.active"

    get "#{operations_root}/api_requests/metrics", headers: headers
    assert_equal requests_body, response.body

    get "#{operations_root}/api_requests/metrics", params: { resource: "api_keys" }, headers: headers
    assert_equal requests_body, response.body

    get "#{operations_root}/metrics", params: { resource: "api_keys" }, headers: headers
    assert_response :success
    keys_body = response.body
    assert_equal(["api_keys.active"], JSON.parse(keys_body).fetch("metrics").map { |row| row.fetch("identifier") })

    get "#{operations_root}/api_keys/metrics", headers: headers
    assert_equal keys_body, response.body

    get "#{operations_root}/typo/metrics", headers: headers
    assert_response :success
    assert_equal({ "metrics" => [] }, JSON.parse(response.body))
  end

  test "resource-first metric show matches the legacy path" do
    headers = bearer_headers(@authorized_token)

    travel_to Time.utc(2026, 6, 1, 12, 0, 0) do
      get "#{operations_root}/metrics/api_requests/rate_limited", headers: headers
      assert_response :success
      canonical = response.body
      assert_equal 4, JSON.parse(canonical).fetch("value")

      get "#{operations_root}/api_requests/metrics/rate_limited", headers: headers
      assert_equal canonical, response.body
    end

    travel_to Time.utc(2026, 6, 1, 12, 0, 0) do
      params = { interval: "day", from: "2026-04-01T00:00:00Z", to: "2026-04-03T00:00:00Z" }
      get "#{operations_root}/metrics/api_requests/over_time", params: params, headers: headers
      over_time = response.body
      get "#{operations_root}/api_requests/metrics/over_time", params: params, headers: headers
      assert_equal over_time, response.body
    end
  end

  test "a site admin resolver that raises denies nested metrics routes" do
    original = RecordingStudioAdmin.configuration.site_admin_recording_resolver
    RecordingStudioAdmin.configuration.site_admin_recording_resolver = ->(*) { raise "resolver failed" }
    headers = bearer_headers(@authorized_token)

    get "#{operations_root}/api_keys/metrics", headers: headers
    assert_response :success
    assert_equal({ "metrics" => [] }, JSON.parse(response.body))

    get "#{operations_root}/api_keys/metrics/active", headers: headers
    assert_response :forbidden
    assert_equal "Not authorized to run this metric", JSON.parse(response.body).dig("error", "message")
  ensure
    RecordingStudioAdmin.configuration.site_admin_recording_resolver = original
  end

  test "public folders/metrics stays on the resource route" do
    user = create_user
    root, access_recording = create_access_recording_for(user: user, role: :edit)
    token = issue_oauth_access_token_for(access_recording: access_recording, name: "Public folders")
    folder = RecordingStudio::Recording.create!(
      recordable: Folder.create!(name: "Kept"),
      parent_recording: root
    )
    RecordingStudioMetrics::Api.register!(api: :public)
    headers = bearer_headers(token)

    get "/recording_studio_api/api/v1/folders/metrics", headers: headers
    assert_response :not_found
    parsed = JSON.parse(response.body)
    refute parsed.key?("metrics")
    assert_equal "not_found", parsed.dig("error", "code")

    get "/recording_studio_api/api/v1/folders/#{folder.id}", headers: headers
    assert_response :success
    assert_equal folder.id, JSON.parse(response.body).fetch("id")

    get "/recording_studio_api/api/v1/folders", headers: headers
    assert_response :success
    listed = JSON.parse(response.body)
    assert_includes listed.fetch("records").map { |row| row.fetch("id") }, folder.id
    refute listed.key?("metrics")
  end

  test "register! adds resource aliases once and leaves other endpoints unchanged" do
    registry = RecordingStudioApi.configuration.fetch_api(:operations).registered_endpoint_registry

    index = registry.fetch("operations_metrics_index")
    alias_index = registry.fetch("operations_metrics_index_for_resource")
    show = registry.fetch("operations_metrics_show")
    alias_show = registry.fetch("operations_metrics_show_for_resource")

    assert_equal "metrics", index.path
    assert_equal ":resource/metrics", alias_index.path
    assert_equal "metrics/:resource/:name", show.path
    assert_equal ":resource/metrics/:name", alias_show.path
    refute_equal RecordingStudioMetrics::Api::DiscoveryHandler, index.handler
    refute_equal RecordingStudioMetrics::Api::ExecuteHandler, show.handler
    assert_same index.handler, alias_index.handler
    assert_same show.handler, alias_show.handler
    resource_query = index.openapi.fetch(:parameters).find { |parameter| parameter.fetch(:name) == "resource" }
    assert_equal "query", resource_query.fetch(:in)
    assert_nil alias_index.openapi[:parameters]
    assert_equal(
      [{ name: "resource", in: "path", required: true, schema: { type: "string" } }],
      alias_index.openapi_path_parameters
    )
    refute_includes show.openapi.fetch(:parameters).map { |parameter| parameter.fetch(:name) }, "resource"
    %w[start_at end_at from to group_by].each do |name|
      matches = show.openapi.fetch(:parameters).select { |parameter| parameter.fetch(:name) == name }
      assert_equal 1, matches.length, name
    end

    handler = ->(_context) { { ok: true } }
    RecordingStudioApi.register_endpoint(
      :ping_metrics_neighbor,
      api: :operations,
      http_verb: :get,
      path: "ping",
      handler: handler
    )
    stored = registry.fetch("ping_metrics_neighbor")
    assert_same handler, stored.handler
    assert_equal "ping", stored.path
    assert_nil stored.openapi[:parameters]
    assert_nil registry["ping_metrics_neighbor_for_resource"]

    RecordingStudioApi.register_endpoint(
      :odd_catalog,
      api: :operations,
      http_verb: :get,
      path: "metrics/:extra",
      handler: RecordingStudioMetrics::Api::DiscoveryHandler
    )
    assert_nil registry["odd_catalog_for_resource"]
    refute_equal RecordingStudioMetrics::Api::DiscoveryHandler, registry.fetch("odd_catalog").handler

    RecordingStudioApi.register_endpoint(
      :slashed_metric,
      api: :operations,
      http_verb: :get,
      path: "/ops/metrics/:resource/:name",
      handler: RecordingStudioMetrics::Api::ExecuteHandler
    )
    assert_equal ":resource/ops/metrics/:name", registry.fetch("slashed_metric_for_resource").path

    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioMetrics::Api.register!(api: :operations)
    end
    assert_equal "API endpoint operations_metrics_index is already registered", error.message
  end

  test "a later literal metrics path beats the resource alias" do
    RecordingStudioApi.register_endpoint(
      :foo_metrics,
      api: :operations,
      http_verb: :get,
      path: "foo/metrics",
      handler: ->(_context) { { hosted: true } }
    )

    get "#{operations_root}/foo/metrics", headers: bearer_headers(@authorized_token)

    assert_response :success
    assert_equal({ "hosted" => true }, JSON.parse(response.body))
  end

  private

  def operations_root
    "/recording_studio_api/apis/operations/v1"
  end

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def seed_daily_metrics!
    RecordingStudioApi::ApiDailyMetric.delete_all
    create_daily_metric(Date.new(2026, 4, 1), 2, 10, 0, 0, 1)
    create_daily_metric(Date.new(2026, 4, 1), 4, 2, 2, 0, 2, "folders")
    create_daily_metric(Date.new(2026, 4, 2), 2, 5, 0, 0, 0)
    create_daily_metric(Date.new(2026, 4, 2), 5, 1, 0, 1, 1, "workspaces")
    create_daily_metric(Date.new(2026, 4, 2), 4, 1, 1, 0, 0, "folders")
  end

  def create_daily_metric(metric_date, status_class, request_count, client_errors, server_errors, rate_limited, route_name = "pages")
    RecordingStudioApi::ApiDailyMetric.create!(
      api_key: "public",
      metric_date: metric_date,
      route_name: route_name,
      controller_name: "RecordingStudioApi::Api::V1::ResourcesController",
      action_name: "index",
      request_method: "GET",
      status_class: status_class,
      request_count: request_count,
      rate_limited_count: rate_limited,
      client_error_count: client_errors,
      server_error_count: server_errors,
      duration_count: request_count,
      duration_sum_ms: request_count * 20,
      duration_max_ms: 20
    )
  end

  def seed_keys!
    root_recording, access_recording = create_access_recording_for(user: @manager)
    provision_api_client_for(access_recording: access_recording, name: "Active metrics key")
    revoked = provision_api_client_for(access_recording: access_recording, name: "Revoked metrics key")
    revoked.fetch(:credential).revoke!
    root_recording
  end

  def issue_operations_token(manager, access_point)
    issued = RecordingStudioApi::Services::IssueTestCredential.call(
      api: :operations,
      actor: manager,
      access_point_recording: access_point,
      role: :view,
      name: "Authorized operations metrics"
    )
    raise issued.error unless issued.success?

    issued.value.fetch(:access_token)
  end

  def issue_unauthorized_operations_token
    outsider = create_user
    root_recording, = create_access_recording_for(user: outsider)
    was_required = RecordingStudioApi.configuration.fetch_api(:operations).api_management_authorization_required
    RecordingStudioApi.configuration.api(:operations) { |api| api.api_management_authorization_required = false }
    issued = RecordingStudioApi::Services::IssueTestCredential.call(
      api: :operations,
      actor: outsider,
      access_point_recording: root_recording,
      role: :view,
      name: "Unauthorized operations metrics"
    )
    RecordingStudioApi.configuration.api(:operations) { |api| api.api_management_authorization_required = was_required }
    raise issued.error unless issued.success?

    issued.value.fetch(:access_token)
  end
end
