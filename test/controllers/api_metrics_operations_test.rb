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
    _admin_root, @admin_recording = create_admin_root_recording(name: "Metrics admin #{SecureRandom.hex(4)}")
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
    assert_empty JSON.parse(response.body).fetch("metrics")

    get "#{operations_root}/metrics/api_keys/active", headers: bearer_headers(@unauthorized_token)
    assert_response :forbidden

    get "#{operations_root}/metrics", headers: bearer_headers(@public_token)
    assert_response :unauthorized
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
