# frozen_string_literal: true

require_relative "support/api_dummy_helpers"

class ApiErrorsOverTimeTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    configure_dummy_operations_api!
    RecordingStudioMetrics.registry.reset!
    RecordingStudioApi::Metrics.register!
  end

  test "errors over time zero-fills the same dates as requests over time" do
    RecordingStudioApi::ApiDailyMetric.delete_all
    window = { interval: :day, start_at: Time.utc(2026, 4, 1), end_at: Time.utc(2026, 4, 4) }

    travel_to Time.utc(2026, 10, 10, 15, 0, 0) do
      over_time = execute("api_requests.over_time", **window)
      errors = execute("api_requests.errors_over_time", **window)
      error_dates = errors.data.map { |row| row[:date] }

      assert_equal over_time.data.map { |row| row[:date] }, error_dates
      assert_equal %w[2026-04-01 2026-04-02 2026-04-03], error_dates
      assert(errors.data.all? { |row| row[:value].zero? })

      default_requests = execute("api_requests.over_time")
      default_errors = execute("api_requests.errors_over_time")
      default_error_dates = default_errors.data.map { |row| row[:date] }
      assert_equal default_requests.data.map { |row| row[:date] }, default_error_dates
      assert_includes default_error_dates, "2026-10-10"
      assert(default_errors.data.all? { |row| row[:value].zero? })
    end
  end

  test "errors over time sums client and server errors inside the window" do
    travel_to Time.utc(2026, 10, 10, 15, 0, 0) do
      RecordingStudioApi::ApiDailyMetric.delete_all
      create_daily_metric(metric_date: Date.new(2026, 10, 10), status_class: 4, request_count: 10, client_error_count: 2, server_error_count: 3)
      create_daily_metric(metric_date: Date.new(2026, 10, 10), status_class: 5, request_count: 1, client_error_count: 1, server_error_count: 0, route_name: "folders")
      create_daily_metric(metric_date: Date.new(2026, 10, 9), status_class: 4, request_count: 8, client_error_count: 4, server_error_count: 1)
      create_daily_metric(metric_date: Date.new(2026, 9, 9), status_class: 5, request_count: 100, client_error_count: 50, server_error_count: 50)
      create_daily_metric(metric_date: Date.new(2026, 10, 11), status_class: 5, request_count: 9, client_error_count: 7, server_error_count: 8)

      over_time = execute("api_requests.over_time")
      errors = execute("api_requests.errors_over_time")
      error_values = errors.data.to_h { |row| [row[:date], row[:value]] }
      request_values = over_time.data.to_h { |row| [row[:date], row[:value]] }

      assert_equal over_time.data.map { |row| row[:date] }, error_values.keys
      assert_includes error_values.keys, "2026-10-10"
      assert_not_includes error_values.keys, "2026-09-09"
      assert_not_includes error_values.keys, "2026-10-11"
      assert_equal 6, error_values["2026-10-10"]
      assert_equal 5, error_values["2026-10-09"]
      assert_equal 0, error_values["2026-10-01"]
      assert_equal 11, request_values["2026-10-10"]

      narrowed = execute(
        "api_requests.errors_over_time",
        interval: :day,
        start_at: Time.utc(2026, 10, 9),
        end_at: Time.utc(2026, 10, 10)
      )
      narrowed_values = narrowed.data.to_h { |row| [row[:date], row[:value]] }
      assert_equal ["2026-10-09"], narrowed_values.keys
      assert_equal 5, narrowed_values["2026-10-09"]
    end
  end

  private

  def execute(identifier, **params)
    RecordingStudioMetrics.execute(
      identifier,
      context: RecordingStudioMetrics::Context.new(
        system: true,
        scope: :site,
        site_authorized: true,
        timezone: "UTC"
      ),
      **params
    )
  end

  def create_daily_metric(metric_date:, status_class:, request_count:, client_error_count:, server_error_count:, route_name: "pages")
    RecordingStudioApi::ApiDailyMetric.create!(
      api_key: "public",
      metric_date: metric_date,
      route_name: route_name,
      controller_name: "RecordingStudioApi::Api::V1::ResourcesController",
      action_name: "index",
      request_method: "GET",
      status_class: status_class,
      request_count: request_count,
      rate_limited_count: 0,
      client_error_count: client_error_count,
      server_error_count: server_error_count,
      duration_count: request_count,
      duration_sum_ms: request_count * 20,
      duration_max_ms: 20
    )
  end
end
