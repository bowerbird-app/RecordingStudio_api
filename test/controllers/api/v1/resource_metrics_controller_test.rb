# frozen_string_literal: true

require "digest"
require_relative "../../../support/api_dummy_helpers"

class ApiV1ResourceMetricsControllerTest < ActionDispatch::IntegrationTest
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    RecordingStudioMetrics.registry.reset!
    RecordingStudioApi::Metrics.register!
    register_folder_metrics!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user, role: :edit)
    @token = issue_oauth_access_token_for(access_recording: @access_recording, name: "Folder metrics")
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    RecordingStudioMetrics.registry.reset!
    RecordingStudioApi::Metrics.register!
    Current.actor = nil if defined?(Current)
  end

  test "lists allowlisted metrics with descriptions and parameters" do
    get "/recording_studio_api/api/v1/folders/metrics", headers: authorization_headers

    assert_response :success
    metrics = JSON.parse(response.body).fetch("metrics")
    assert_equal(%w[folders.alpha folders.created_over_time folders.total], metrics.map { |metric| metric.fetch("name") })
    assert_equal "Folder count", metrics.fetch(0).fetch("description")
    assert_equal "Folders created in the window.", metrics.fetch(1).fetch("description")
    assert_equal "How many folders are in this scope.", metrics.fetch(2).fetch("description")

    alpha = metrics.fetch(0)
    assert_equal(%w[q filter[name]], alpha.fetch("parameters").map { |parameter| parameter.fetch("name") })
    assert_equal "count", alpha.fetch("unit")
    assert_equal "Folder count", alpha.fetch("title")
    assert_equal "UTC", alpha.fetch("timezone")
    assert_equal false, alpha.dig("freshness", "cached")

    created_parameters = metrics.fetch(1).fetch("parameters")
    assert_equal(%w[from to interval group_by q filter[name]], created_parameters.map { |parameter| parameter.fetch("name") })
    assert_equal %w[day week], created_parameters.find { |parameter| parameter.fetch("name") == "interval" }.dig("schema", "enum")
    assert_equal ["name"], created_parameters.find { |parameter| parameter.fetch("name") == "group_by" }.dig("schema", "enum")
    assert_equal(
      "Case-insensitive substring search across filterable attributes for this resource.",
      created_parameters.find { |parameter| parameter.fetch("name") == "q" }.fetch("description")
    )
    assert_equal(
      "Exact match filter on name.",
      created_parameters.find { |parameter| parameter.fetch("name") == "filter[name]" }.fetch("description")
    )
  end

  test "counts only accessible folders and applies list filters" do
    create_folder("Ada")
    create_folder("Bea")
    other_root, = create_access_recording_for(user: create_user, role: :admin)
    RecordingStudio::Recording.create!(recordable: Folder.create!(name: "Ada"), parent_recording: other_root)

    get "/recording_studio_api/api/v1/folders/metrics/folders.total", headers: authorization_headers

    assert_response :success
    assert_equal 2, JSON.parse(response.body).fetch("value")

    get "/recording_studio_api/api/v1/folders/metrics/folders.total",
        params: { filter: { name: "Ada" } },
        headers: authorization_headers

    assert_response :success
    assert_equal 1, JSON.parse(response.body).fetch("value")

    get "/recording_studio_api/api/v1/folders/metrics/folders.total",
        params: { q: "Bea" },
        headers: authorization_headers

    assert_response :success
    assert_equal 1, JSON.parse(response.body).fetch("value")
  end

  test "execute receives cache false and the filtered authorized relation" do
    ada = create_folder("Ada")
    create_folder("Bea")
    captured = nil
    result = RecordingStudioMetrics::Result.new(
      metric: "folders.created_over_time",
      type: :timeseries,
      data: [],
      unit: "count",
      title: "Created over time"
    )

    RecordingStudioMetrics.stub(:execute, lambda { |name, **kwargs|
      captured = { name: name, kwargs: kwargs }
      result
    }) do
      get "/recording_studio_api/api/v1/folders/metrics/folders.created_over_time",
          params: { from: "2026-04-01T00:00:00Z", to: "2026-04-03T00:00:00Z", interval: "day", group_by: "name", filter: { name: "Ada" }, q: "Ada" },
          headers: authorization_headers
    end

    assert_response :success
    assert_equal [], JSON.parse(response.body).fetch("data")
    assert_equal "folders.created_over_time", captured.fetch(:name)
    kwargs = captured.fetch(:kwargs)
    assert_equal false, kwargs.fetch(:cache)
    assert_equal({}, kwargs.fetch(:filters))
    assert_equal "day", kwargs.fetch(:interval)
    assert_equal "2026-04-01T00:00:00Z", kwargs.fetch(:start_at)
    assert_equal "2026-04-03T00:00:00Z", kwargs.fetch(:end_at)
    assert_equal "name", kwargs.fetch(:group_by)
    context = kwargs.fetch(:context)
    assert_nil context.root_recording
    assert_nil context.access_recording
    assert_nil context.workspace_id
    assert_equal :root, context.scope
    assert_equal false, context.site_authorized?
    assert_equal [ada.recordable_id], context.authorized_relation.pluck(:id)
  end

  test "view denial is forbidden and an unknown name is not found" do
    get "/recording_studio_api/api/v1/folders/metrics/folders.missing", headers: authorization_headers

    assert_response :not_found
    missing = JSON.parse(response.body)
    refute missing.key?("metrics")
    assert_equal "not_found", missing.dig("error", "code")
    assert_equal "Metric folders.missing is not available on this resource", missing.dig("error", "message")

    client_access = RecordingStudioApi::ApiClient.find_by!(name: "Folder metrics").access_recording
    RecordingStudio::Access.where(id: client_access.recordable_id).update_all(role: "guest")
    ActiveRecord::Base.connection.clear_query_cache

    get "/recording_studio_api/api/v1/folders/metrics", headers: authorization_headers
    assert_response :forbidden
    denied = JSON.parse(response.body)
    refute denied.key?("metrics")
    assert_equal "forbidden", denied.dig("error", "code")
    assert_equal "API access grant is not authorized for this capability", denied.dig("error", "message")

    get "/recording_studio_api/api/v1/folders/metrics/folders.missing", headers: authorization_headers
    assert_response :forbidden
    assert_equal "API access grant is not authorized for this capability", JSON.parse(response.body).dig("error", "message")
  end

  test "pages metrics stays on show and folder routes resolve in the public and named draw blocks" do
    get "/recording_studio_api/api/v1/pages/metrics", headers: authorization_headers

    assert_response :not_found
    parsed = JSON.parse(response.body)
    refute parsed.key?("metrics")
    assert_equal "not_found", parsed.dig("error", "code")

    public_index = Rails.application.routes.recognize_path("/recording_studio_api/api/v1/folders/metrics", method: :get)
    assert_equal "recording_studio_api/api/v1/resource_metrics", public_index[:controller]
    assert_equal "index", public_index[:action]

    public_show = Rails.application.routes.recognize_path("/recording_studio_api/api/v1/folders/metrics/folders.total", method: :get)
    assert_equal "recording_studio_api/api/v1/resource_metrics", public_show[:controller]
    assert_equal "show", public_show[:action]
    assert_equal "folders.total", public_show[:name]

    page_show = Rails.application.routes.recognize_path("/recording_studio_api/api/v1/pages/metrics", method: :get)
    assert_equal "recording_studio_api/api/v1/resources", page_show[:controller]
    assert_equal "show", page_show[:action]
    assert_equal "metrics", page_show[:id]

    configure_dummy_operations_api!
    RecordingStudioApi.register_recordable_type_api(
      "Folder",
      api: :operations,
      serializer: ->(recordable, **) { { name: recordable.name } },
      output_keys: %i[name],
      metrics: %w[folders.total]
    )
    named_index = Rails.application.routes.recognize_path("/recording_studio_api/apis/operations/v1/folders/metrics", method: :get)
    assert_equal "recording_studio_api/api/v1/resource_metrics", named_index[:controller]
    assert_equal "index", named_index[:action]
    assert_equal "operations", named_index[:api_key]
  end

  test "openapi documents one metrics path and keeps interval and group_by enums" do
    document = RecordingStudioApi::Services::OpenapiDocument.call
    paths = document.fetch(:paths)
    show_path = "/recording_studio_api/api/v1/folders/metrics/{name}"
    operation = paths.fetch(show_path).fetch("get")
    raw_path = "/recording_studio_api/api/v1/folders/metrics/:name"

    assert_equal "resource_metrics_show_get_#{Digest::SHA1.hexdigest(raw_path)[0, 8]}", operation.fetch(:operationId)
    assert_equal(
      %w[name q filter[name] from to interval group_by],
      operation.fetch(:parameters).map { |parameter| parameter.fetch("name") }
    )
    assert_equal true, operation.fetch(:parameters).find { |parameter| parameter.fetch("name") == "name" }.fetch("required")
    assert_equal "path", operation.fetch(:parameters).find { |parameter| parameter.fetch("name") == "name" }.fetch("in")
    assert_nil operation.fetch(:parameters).find { |parameter| parameter.fetch("name") == "interval" }.dig("schema", "enum")
    assert_nil operation.fetch(:parameters).find { |parameter| parameter.fetch("name") == "group_by" }.dig("schema", "enum")
    from_parameter = operation.fetch(:parameters).find { |parameter| parameter.fetch("name") == "from" }
    assert_includes from_parameter.fetch("description"), "start must match from"
    get "/recording_studio_api/api/v1/folders/metrics", headers: authorization_headers
    listed = JSON.parse(response.body).fetch("metrics")
    created = listed.find { |metric| metric.fetch("name") == "folders.created_over_time" }
    assert_equal %w[day week], created.fetch("parameters").find { |parameter| parameter.fetch("name") == "interval" }.dig("schema", "enum")
    assert_equal [], paths.fetch("/recording_studio_api/api/v1/folders/metrics").fetch("get").fetch(:parameters)
    refute paths.key?("/recording_studio_api/api/v1/folders/metrics/folders.total")
    refute paths.key?("/recording_studio_api/api/v1/folders/metrics/folders.alpha")
  end

  test "metric count matches the list count and skips trash and another root" do
    create_folder("Ada")
    create_folder("Bea")
    gone = create_folder("Gone")
    gone.update_column(:trashed_at, Time.current)
    other_root, = create_access_recording_for(user: create_user, role: :admin)
    RecordingStudio::Recording.create!(recordable: Folder.create!(name: "Other"), parent_recording: other_root)

    get "/recording_studio_api/api/v1/folders", params: { count: "true" }, headers: authorization_headers
    assert_response :success
    list_count = JSON.parse(response.body).fetch("total_count")

    get "/recording_studio_api/api/v1/folders/metrics/folders.total", headers: authorization_headers
    assert_response :success
    metric_count = JSON.parse(response.body).fetch("value")

    assert_equal list_count, metric_count
    assert_equal 2, metric_count
    assert_operator metric_count, :<, Folder.count
  end

  test "a scope proc is a configuration error on the catalog and the metric" do
    reregister_folder_metrics!(%w[folders.leaky], scope: ->(_) { Folder.all }) do
      count :leaky, title: "Leaky"
    end

    get "/recording_studio_api/api/v1/folders/metrics", headers: authorization_headers
    error = assert_api_error(:unprocessable_entity, "invalid_input")
    assert_equal "Metric folders.leaky declares a scope", error.fetch("message")

    get "/recording_studio_api/api/v1/folders/metrics/folders.leaky", headers: authorization_headers
    error = assert_api_error(:unprocessable_entity, "invalid_input")
    assert_equal "Metric folders.leaky declares a scope", error.fetch("message")
  end

  test "one ineligible metric fails the catalog and a good neighbor" do
    reregister_folder_metrics!(%w[folders.total folders.filtered]) do
      count :total, title: "Folders", description: "How many folders are in this scope."
      count :filtered, title: "Filtered" do
        filter :status, type: :string, field: :name
      end
    end

    get "/recording_studio_api/api/v1/folders/metrics", headers: authorization_headers
    error = assert_api_error(:unprocessable_entity, "invalid_input")
    assert_equal "Metric folders.filtered declares metric filters", error.fetch("message")

    get "/recording_studio_api/api/v1/folders/metrics/folders.total", headers: authorization_headers
    error = assert_api_error(:unprocessable_entity, "invalid_input")
    assert_equal "Metric folders.filtered declares metric filters", error.fetch("message")
  end

  test "metrics are unsupported when index is disabled" do
    reregister_folder_metrics!(%w[folders.total], operations: %i[show]) do
      count :total, title: "Folders", description: "How many folders are in this scope."
    end

    get "/recording_studio_api/api/v1/folders", headers: authorization_headers
    list_error = assert_api_error(:unprocessable_entity, "unsupported_action")

    get "/recording_studio_api/api/v1/folders/metrics", headers: authorization_headers
    catalog_error = assert_api_error(:unprocessable_entity, "unsupported_action")
    assert_equal list_error.fetch("message"), catalog_error.fetch("message")
    assert_equal "index is not enabled for Folder", catalog_error.fetch("message")

    get "/recording_studio_api/api/v1/folders/metrics/folders.total", headers: authorization_headers
    show_error = assert_api_error(:unprocessable_entity, "unsupported_action")
    assert_equal "index is not enabled for Folder", show_error.fetch("message")
  end

  test "view and admin can read metrics and a guest cannot" do
    create_folder("Ada")
    view_token = token_for(role: :view)
    admin_token = token_for(role: :admin)

    [view_token, admin_token].each do |token|
      get "/recording_studio_api/api/v1/folders/metrics", headers: bearer(token)
      assert_response :success
      get "/recording_studio_api/api/v1/folders/metrics/folders.total", headers: bearer(token)
      assert_response :success
      assert_equal 0, JSON.parse(response.body).fetch("value")
    end

    guest_token = token_for(role: :guest)
    get "/recording_studio_api/api/v1/folders/metrics", headers: bearer(guest_token)
    assert_api_error(:forbidden, "forbidden")
    get "/recording_studio_api/api/v1/folders/metrics/folders.total", headers: bearer(guest_token)
    error = assert_api_error(:forbidden, "forbidden")
    assert_equal "API access grant is not authorized for this capability", error.fetch("message")
  end

  test "a missing token is unauthorized" do
    get "/recording_studio_api/api/v1/folders/metrics"
    assert_api_error(:unauthorized, "authentication_failed")

    get "/recording_studio_api/api/v1/folders/metrics/folders.total", headers: { "Authorization" => "Bearer invalid-token" }
    assert_api_error(:unauthorized, "authentication_failed")
    assert_equal 'Bearer realm="RecordingStudioApi"', response.headers["WWW-Authenticate"]
  end

  test "a folder scoped grant counts that folder and not a sibling" do
    parent = create_folder("Parent")
    RecordingStudio::Recording.create!(recordable: Folder.create!(name: "Child"), parent_recording: parent)
    create_folder("Sibling")
    user = create_user
    access = grant_or_bootstrap_access!(recording: parent, actor: user, role: :view)
    token = issue_oauth_access_token_for(access_recording: access, name: "Folder scoped metrics")
    headers = bearer(token)

    get "/recording_studio_api/api/v1/folders", params: { count: "true" }, headers: headers
    assert_response :success
    list_count = JSON.parse(response.body).fetch("total_count")

    get "/recording_studio_api/api/v1/folders/metrics/folders.total", headers: headers
    assert_response :success
    metric_count = JSON.parse(response.body).fetch("value")

    assert_equal 2, list_count
    assert_equal list_count, metric_count
    assert_operator metric_count, :<, Folder.count
  end

  test "array and hash filters are rejected on the list and on metrics" do
    get "/recording_studio_api/api/v1/folders", params: { filter: { name: ["Ada"] } }, headers: authorization_headers
    error = assert_api_error(:unprocessable_entity, "invalid_input")
    assert_equal "filter[name] must be a single value", error.fetch("message")

    get "/recording_studio_api/api/v1/folders/metrics/folders.total",
        params: { filter: { name: { gt: "Ada" } } },
        headers: authorization_headers
    error = assert_api_error(:unprocessable_entity, "invalid_input")
    assert_equal "filter[name] must be a single value", error.fetch("message")
  end

  test "unknown filters are rejected instead of ignored" do
    create_folder("Ada")

    get "/recording_studio_api/api/v1/folders/metrics/folders.total",
        params: { filter: { missing: "Ada" } },
        headers: authorization_headers
    error = assert_api_error(:unprocessable_entity, "invalid_input")
    assert_equal "Unknown filters: missing", error.fetch("message")

    get "/recording_studio_api/api/v1/folders", params: { filter: { missing: "Ada" } }, headers: authorization_headers
    error = assert_api_error(:unprocessable_entity, "invalid_input")
    assert_equal "Unknown filters: missing", error.fetch("message")
  end

  test "structured window params and scalar window params are rejected" do
    get "/recording_studio_api/api/v1/folders/metrics/folders.created_over_time",
        params: { interval: ["day"] },
        headers: authorization_headers
    error = assert_api_error(:unprocessable_entity, "invalid_input")
    assert_equal "interval must be a single value", error.fetch("message")

    get "/recording_studio_api/api/v1/folders/metrics/folders.total",
        params: { from: "2026-04-01T00:00:00Z", interval: "day" },
        headers: authorization_headers
    error = assert_api_error(:unprocessable_entity, "invalid_input")
    assert_equal "from is not accepted for this metric", error.fetch("message")

    get "/recording_studio_api/api/v1/folders/metrics/folders.created_over_time",
        params: { from: "not-a-date", to: "2026-04-03T00:00:00Z", interval: "day" },
        headers: authorization_headers
    error = assert_api_error(:unprocessable_entity, "invalid_input")
    assert_equal "invalid time value", error.fetch("message")

    get "/recording_studio_api/api/v1/folders/metrics/folders.created_over_time",
        params: { start: "2026-04-01T00:00:00Z", from: "2026-04-02T00:00:00Z", to: "2026-04-03T00:00:00Z", interval: "day" },
        headers: authorization_headers
    error = assert_api_error(:unprocessable_entity, "invalid_input")
    assert_equal "start and from must match when both are provided", error.fetch("message")

    get "/recording_studio_api/api/v1/folders/metrics/folders.total",
        params: { timezone: "America/New_York" },
        headers: authorization_headers
    error = assert_api_error(:unprocessable_entity, "invalid_input")
    assert_equal "timezone is not accepted for this metric", error.fetch("message")
  end

  test "a field count windows the relation and rejects a garbage bound" do
    reregister_folder_metrics!(%w[folders.windowed]) do
      count :windowed, title: "Windowed", description: "Folders in the window.", field: :created_at
    end
    Folder.where(id: create_folder("Old").recordable_id).update_all(created_at: Time.zone.parse("2020-01-01T00:00:00Z"))
    Folder.where(id: create_folder("New").recordable_id).update_all(created_at: Time.zone.parse("2026-04-02T00:00:00Z"))

    get "/recording_studio_api/api/v1/folders/metrics", headers: authorization_headers
    assert_response :success
    windowed = JSON.parse(response.body).fetch("metrics").fetch(0)
    assert_equal(%w[from to q filter[name]], windowed.fetch("parameters").map { |parameter| parameter.fetch("name") })

    get "/recording_studio_api/api/v1/folders/metrics/folders.windowed",
        params: { from: "2026-04-01T00:00:00Z", to: "2026-04-03T00:00:00Z" },
        headers: authorization_headers
    assert_response :success
    assert_equal 1, JSON.parse(response.body).fetch("value")

    get "/recording_studio_api/api/v1/folders/metrics/folders.windowed", headers: authorization_headers
    assert_response :success
    assert_equal 2, JSON.parse(response.body).fetch("value")

    get "/recording_studio_api/api/v1/folders/metrics/folders.windowed",
        params: { from: "not-a-date" },
        headers: authorization_headers
    error = assert_api_error(:unprocessable_entity, "invalid_input")
    assert_equal "invalid time value", error.fetch("message")

    get "/recording_studio_api/api/v1/folders/metrics/folders.windowed",
        params: { interval: "day" },
        headers: authorization_headers
    error = assert_api_error(:unprocessable_entity, "invalid_input")
    assert_equal "interval is not accepted for this metric", error.fetch("message")
  end

  test "a long metric name and a stacked json suffix stay in the api error body" do
    long_name = "n" * 200
    get "/recording_studio_api/api/v1/folders/metrics/#{long_name}", headers: authorization_headers
    error = assert_api_error(:not_found, "not_found")
    assert_includes error.fetch("message"), "..."
    refute_includes error.fetch("message"), long_name

    stacked = Rails.application.routes.recognize_path(
      "/recording_studio_api/api/v1/folders/metrics.json.json",
      method: :get
    )
    assert_equal "recording_studio_api/api/v1/resource_metrics", stacked[:controller]
    assert_equal "index", stacked[:action]

    get "/recording_studio_api/api/v1/folders/metrics.json.json", headers: authorization_headers
    error = assert_api_error(:not_found, "not_found")
    assert_equal "Request format is not supported", error.fetch("message")
  end

  private

  def register_folder_metrics!
    RecordingStudioApi.register_recordable_type_api(
      "Folder",
      metrics: %w[folders.alpha folders.created_over_time folders.total]
    )
    RecordingStudioMetrics.register(:folders, model: Folder, blast_radius: :root) do
      count :alpha, title: "Folder count"
      timeseries :created_over_time,
                 title: "Created over time",
                 description: "Folders created in the window.",
                 field: :created_at,
                 intervals: %i[day week],
                 group_by: %i[name]
      count :total, title: "Folders", description: "How many folders are in this scope."
    end
  end

  def create_folder(name)
    RecordingStudio::Recording.create!(
      recordable: Folder.create!(name: name),
      parent_recording: @root_recording
    )
  end

  def authorization_headers
    bearer(@token)
  end

  def bearer(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def token_for(role:)
    _root, access = create_access_recording_for(user: create_user, role: role == :guest ? :view : role)
    token = issue_oauth_access_token_for(access_recording: access, name: "#{role} metrics")
    return token unless role == :guest

    client_access = RecordingStudioApi::ApiClient.find_by!(name: "guest metrics").access_recording
    RecordingStudio::Access.where(id: client_access.recordable_id).update_all(role: "guest")
    ActiveRecord::Base.connection.clear_query_cache
    token
  end

  def reregister_folder_metrics!(names, scope: nil, **registration, &)
    reset_recording_studio_api_configuration!
    RecordingStudioMetrics.registry.reset!
    RecordingStudioApi::Metrics.register!
    RecordingStudioApi.register_recordable_type_api("Folder", metrics: names, **registration)
    options = { model: Folder, blast_radius: :root }
    options[:scope] = scope if scope
    RecordingStudioMetrics.register(:folders, **options, &)
  end

  def assert_api_error(status, code)
    assert_response status
    assert_match %r{application/json}, response.content_type
    parsed = JSON.parse(response.body)
    refute parsed.key?("metrics")
    assert_equal code, parsed.dig("error", "code")
    parsed.fetch("error")
  end
end
