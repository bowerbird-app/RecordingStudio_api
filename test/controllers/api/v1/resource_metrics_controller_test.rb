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

    alpha_parameters = metrics.fetch(0).fetch("parameters")
    assert_equal(%w[from to interval group_by q filter[name]], alpha_parameters.map { |parameter| parameter.fetch("name") })
    assert_nil alpha_parameters.find { |parameter| parameter.fetch("name") == "interval" }.dig("schema", "enum")

    created_parameters = metrics.fetch(1).fetch("parameters")
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
      metric: "folders.total",
      type: :scalar,
      value: 7,
      unit: "count",
      title: "Folders"
    )

    RecordingStudioMetrics.stub(:execute, lambda { |name, **kwargs|
      captured = { name: name, kwargs: kwargs }
      result
    }) do
      get "/recording_studio_api/api/v1/folders/metrics/folders.total",
          params: { from: "2026-04-01T00:00:00Z", to: "2026-04-03T00:00:00Z", interval: "day", group_by: "name", filter: { name: "Ada" }, q: "Ada" },
          headers: authorization_headers
    end

    assert_response :success
    assert_equal 7, JSON.parse(response.body).fetch("value")
    assert_equal "folders.total", captured.fetch(:name)
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
      %w[name from to interval group_by q filter[name]],
      operation.fetch(:parameters).map { |parameter| parameter.fetch("name") }
    )
    assert_equal true, operation.fetch(:parameters).find { |parameter| parameter.fetch("name") == "name" }.fetch("required")
    assert_equal "path", operation.fetch(:parameters).find { |parameter| parameter.fetch("name") == "name" }.fetch("in")
    assert_equal %w[day week], operation.fetch(:parameters).find { |parameter| parameter.fetch("name") == "interval" }.dig("schema", "enum")
    assert_equal ["name"], operation.fetch(:parameters).find { |parameter| parameter.fetch("name") == "group_by" }.dig("schema", "enum")
    assert_equal [], paths.fetch("/recording_studio_api/api/v1/folders/metrics").fetch("get").fetch(:parameters)
    refute paths.key?("/recording_studio_api/api/v1/folders/metrics/folders.total")
    refute paths.key?("/recording_studio_api/api/v1/folders/metrics/folders.alpha")
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
    { "Authorization" => "Bearer #{@token}" }
  end
end
