# frozen_string_literal: true

require "test_helper"

class ApiMetricsTest < ActionDispatch::IntegrationTest
  PASSWORD = "ApiMetricsPassword!2026"

  setup do
    RecordingStudioMetrics.registry.reset!
    RecordingStudioApi::Metrics.register!
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      api: :operations,
      operations: %i[index show],
      serializer: ->(recordable, **) { { name: recordable.name } },
      output_keys: %i[name]
    ) unless RecordingStudioApi.recordable_registration_for("Workspace", api: :operations)
    RecordingStudioMetrics::Api.register!(api: :operations) unless RecordingStudioApi.registered_endpoint(:operations_metrics_index, api: :operations)

    @actor = create_user("metrics-manager-#{SecureRandom.hex(4)}@example.com")
    @outsider = create_user("metrics-outsider-#{SecureRandom.hex(4)}@example.com")
    @admin_root = AdminRoot.find_or_create_by!(name: "Admin")
    @admin_recording = RecordingStudio.root_recording_for(@admin_root)
    RecordingStudioApi::Admin::ApiAuthorization.recording_for(
      api: :operations,
      root_recording: @admin_recording,
      create: true
    )
    grant_admin!(@actor, @admin_recording)

    seed_daily_metrics!
    seed_api_keys!

    @authorized_token = issue_operations_token(manager: @actor, access_point: @admin_recording)
    @unauthorized_token = issue_workspace_operations_token
    @public_token = issue_public_token
  end

  test "registers the api request and key metrics on the operations API" do
    request_ids = RecordingStudioMetrics.for_resource(:api_requests).map(&:identifier)
    key_ids = RecordingStudioMetrics.for_resource(:api_keys).map(&:identifier)

    assert_equal %w[
      api_requests.by_status_class
      api_requests.errors_over_time
      api_requests.over_time
      api_requests.rate_limited
    ], request_ids.sort
    assert_equal ["api_keys.active"], key_ids

    RecordingStudioMetrics.for_resource(:api_requests).each do |definition|
      assert_equal [:operations], definition.exposed_apis
      assert_equal :site, definition.blast_radius
    end
    RecordingStudioMetrics.for_resource(:api_keys).each do |definition|
      assert_equal [:operations], definition.exposed_apis
      assert_equal :site, definition.blast_radius
    end
  end

  test "metric values sum seeded daily rows and exclude revoked keys" do
    over_time = execute("api_requests.over_time", interval: :day, start_at: Time.utc(2026, 4, 1), end_at: Time.utc(2026, 4, 4))
    values = over_time.data.to_h { |row| [row[:date], row[:value]] }
    assert_equal 12, values["2026-04-01"]
    assert_equal 7, values["2026-04-02"]

    errors = execute("api_requests.errors_over_time", interval: :day, start_at: Time.utc(2026, 4, 1), end_at: Time.utc(2026, 4, 4))
    error_values = errors.data.to_h { |row| [row[:date], row[:value]] }
    assert_equal 2, error_values["2026-04-01"]
    assert_equal 2, error_values["2026-04-02"]

    breakdown = execute("api_requests.by_status_class")
    by_class = breakdown.data.to_h { |row| [row[:key].to_i, row[:value]] }
    assert_equal 15, by_class[2]
    assert_equal 3, by_class[4]
    assert_equal 1, by_class[5]

    rate_limited = execute("api_requests.rate_limited")
    assert_equal 4, rate_limited.value

    active_keys = execute("api_keys.active")
    assert_equal RecordingStudioApi::ApiCredential.active.count, active_keys.value
    assert_operator RecordingStudioApi::ApiCredential.where.not(revoked_at: nil).count, :>=, 1
    assert_operator active_keys.value, :<, RecordingStudioApi::ApiCredential.count
  end

  test "operations metrics index lists registered metrics for an authorized management token" do
    get "#{operations_root}/metrics", headers: bearer(@authorized_token)

    assert_response :success
    identifiers = JSON.parse(response.body).fetch("metrics").map { |row| row.fetch("identifier") }
    assert_includes identifiers, "api_requests.over_time"
    assert_includes identifiers, "api_requests.errors_over_time"
    assert_includes identifiers, "api_requests.by_status_class"
    assert_includes identifiers, "api_requests.rate_limited"
    assert_includes identifiers, "api_keys.active"
  end

  test "authorized management operations token can execute metrics" do
    get "#{operations_root}/metrics/api_keys/active", headers: bearer(@authorized_token)

    assert_response :success
    assert_equal RecordingStudioApi::ApiCredential.active.count, JSON.parse(response.body).fetch("value")
  end

  test "unauthorized operations token and public token are denied" do
    get "#{operations_root}/metrics", headers: bearer(@unauthorized_token)
    assert_response :success
    assert_empty JSON.parse(response.body).fetch("metrics")

    get "#{operations_root}/metrics/api_keys/active", headers: bearer(@unauthorized_token)
    assert_response :forbidden

    get "#{operations_root}/metrics", headers: bearer(@public_token)
    assert_response :unauthorized

    get "#{operations_root}/metrics/api_requests/over_time", headers: bearer(@public_token)
    assert_response :unauthorized
  end

  private

  def execute(identifier, **params)
    RecordingStudioMetrics.execute(
      identifier,
      context: RecordingStudioMetrics::Context.new(
        actor: @actor,
        scope: :site,
        site_authorized: true,
        timezone: "UTC"
      ),
      **params
    )
  end

  def operations_root
    "/recording_studio_api/apis/operations/v1"
  end

  def bearer(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def create_user(email)
    User.create!(email: email, password: PASSWORD, password_confirmation: PASSWORD)
  end

  def grant_admin!(actor, recording)
    Current.actor = actor
    result = RecordingStudioAccessible.bootstrap_owner_access!(recording: recording, actor: actor)
    return result.value if result.respond_to?(:success?) && result.success?

    access = RecordingStudio::Access.create!(actor: actor, role: :admin)
    RecordingStudio::Recording.create!(recordable: access, parent_recording: recording)
  end

  def seed_daily_metrics!
    RecordingStudioApi::ApiDailyMetric.delete_all
    create_daily_metric(metric_date: Date.new(2026, 4, 1), status_class: 2, request_count: 10, client_error_count: 0, server_error_count: 0, rate_limited_count: 1)
    create_daily_metric(metric_date: Date.new(2026, 4, 1), status_class: 4, request_count: 2, client_error_count: 2, server_error_count: 0, rate_limited_count: 2, route_name: "folders")
    create_daily_metric(metric_date: Date.new(2026, 4, 2), status_class: 2, request_count: 5, client_error_count: 0, server_error_count: 0, rate_limited_count: 0)
    create_daily_metric(metric_date: Date.new(2026, 4, 2), status_class: 5, request_count: 1, client_error_count: 0, server_error_count: 1, rate_limited_count: 1, route_name: "workspaces")
    create_daily_metric(metric_date: Date.new(2026, 4, 2), status_class: 4, request_count: 1, client_error_count: 1, server_error_count: 0, rate_limited_count: 0, route_name: "folders")
  end

  def create_daily_metric(metric_date:, status_class:, request_count:, client_error_count:, server_error_count:, rate_limited_count:, route_name: "pages")
    RecordingStudioApi::ApiDailyMetric.create!(
      api_key: "public",
      metric_date: metric_date,
      route_name: route_name,
      controller_name: "RecordingStudioApi::Api::V1::ResourcesController",
      action_name: "index",
      request_method: "GET",
      status_class: status_class,
      request_count: request_count,
      rate_limited_count: rate_limited_count,
      client_error_count: client_error_count,
      server_error_count: server_error_count,
      duration_count: request_count,
      duration_sum_ms: request_count * 20,
      duration_max_ms: 20
    )
  end

  def seed_api_keys!
    workspace = Workspace.create!(name: "Metrics keys #{SecureRandom.hex(4)}")
    root = RecordingStudio::Recording.create!(recordable: workspace)
    access = grant_admin!(@actor, root)
    active = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_point_recording: root,
      manager_actor: @actor,
      role: :admin,
      name: "Active metrics key #{SecureRandom.hex(4)}"
    )
    raise active.error unless active.success?

    revoked = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_point_recording: root,
      manager_actor: @actor,
      role: :admin,
      name: "Revoked metrics key #{SecureRandom.hex(4)}"
    )
    raise revoked.error unless revoked.success?

    revoked.value.fetch(:credential).revoke!
    access
  end

  def issue_operations_token(manager:, access_point:)
    issued = RecordingStudioApi::Services::IssueTestCredential.call(
      api: :operations,
      actor: manager,
      access_point_recording: access_point,
      role: :view,
      name: "Authorized operations metrics #{SecureRandom.hex(4)}"
    )
    raise issued.error unless issued.success?

    issued.value.fetch(:access_token)
  end

  def issue_workspace_operations_token
    workspace = Workspace.create!(name: "Unauthorized ops #{SecureRandom.hex(4)}")
    root = RecordingStudio::Recording.create!(recordable: workspace)
    grant_admin!(@outsider, root)

    was_required = RecordingStudioApi.configuration.fetch_api(:operations).api_management_authorization_required
    RecordingStudioApi.configuration.api(:operations) { |api| api.api_management_authorization_required = false }
    issued = RecordingStudioApi::Services::IssueTestCredential.call(
      api: :operations,
      actor: @outsider,
      access_point_recording: root,
      role: :view,
      name: "Unauthorized operations metrics #{SecureRandom.hex(4)}"
    )
    RecordingStudioApi.configuration.api(:operations) { |api| api.api_management_authorization_required = was_required }
    raise issued.error unless issued.success?

    issued.value.fetch(:access_token)
  end

  def issue_public_token
    workspace = Workspace.create!(name: "Public metrics #{SecureRandom.hex(4)}")
    root = RecordingStudio::Recording.create!(recordable: workspace)
    grant_admin!(@outsider, root)
    issued = RecordingStudioApi::Services::IssueTestCredential.call(
      api: :public,
      actor: @outsider,
      access_point_recording: root,
      role: :view,
      name: "Public metrics #{SecureRandom.hex(4)}"
    )
    raise issued.error unless issued.success?

    issued.value.fetch(:access_token)
  end
end
