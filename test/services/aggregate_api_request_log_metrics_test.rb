# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "../test_helper"
require_relative "../dummy/config/environment"

class AggregateApiRequestLogMetricsTest < ActiveSupport::TestCase
  setup do
    @metric_date = Date.new(2026, 8, 2)
    RecordingStudioApi::ApiRequestLog.delete_all
    RecordingStudioApi::ApiDailyMetric.delete_all
    RecordingStudioApi::ApiDailyLatencyHistogramBucket.delete_all
  end

  test "returns false when a required metrics table is unavailable" do
    RecordingStudioApi::ApiRequestLog.stub(:table_available?, false) do
      refute RecordingStudioApi::Services::AggregateApiRequestLogMetrics.call(metric_date: @metric_date)
    end

    assert_equal 0, RecordingStudioApi::ApiDailyMetric.count
    assert_equal 0, RecordingStudioApi::ApiDailyLatencyHistogramBucket.count
  end

  test "aggregates request statuses, rate limits, and latency buckets" do
    create_log(route_name: "pages", request_method: "GET", status_code: 200, duration_ms: 25)
    create_log(route_name: "pages", request_method: "GET", status_code: 429, duration_ms: 26)
    create_log(route_name: "pages", request_method: "GET", status_code: 500, duration_ms: 30_001, rate_limited: true)
    create_log(route_name: nil, request_method: "POST", status_code: 404, duration_ms: 100)
    create_log(metric_date: @metric_date - 1.day, route_name: "pages", request_method: "GET", status_code: 200, duration_ms: 50)

    assert RecordingStudioApi::Services::AggregateApiRequestLogMetrics.call(metric_date: @metric_date)

    pages_metric = RecordingStudioApi::ApiDailyMetric.find_by!(route_name: "pages", request_method: "GET", status_class: 2)
    assert_equal 1, pages_metric.request_count
    assert_equal 0, pages_metric.rate_limited_count
    assert_equal 0, pages_metric.client_error_count
    assert_equal 0, pages_metric.server_error_count
    assert_equal 1, pages_metric.duration_count
    assert_equal 25, pages_metric.duration_sum_ms
    assert_equal 25, pages_metric.duration_max_ms

    throttled_metric = RecordingStudioApi::ApiDailyMetric.find_by!(route_name: "pages", request_method: "GET", status_class: 4)
    assert_equal 1, throttled_metric.rate_limited_count
    assert_equal 1, throttled_metric.client_error_count

    server_error_metric = RecordingStudioApi::ApiDailyMetric.find_by!(route_name: "pages", request_method: "GET", status_class: 5)
    assert_equal 1, server_error_metric.rate_limited_count
    assert_equal 1, server_error_metric.server_error_count

    public_metric = RecordingStudioApi::ApiDailyMetric.find_by!(route_name: "unknown", request_method: "POST", status_class: 4)
    assert_equal "public", public_metric.api_key
    assert_equal 1, public_metric.client_error_count

    assert_equal [25, 50, 30_000], RecordingStudioApi::ApiDailyLatencyHistogramBucket.where(route_name: "pages").order(:upper_bound_ms).pluck(:upper_bound_ms)
    assert_equal 4, RecordingStudioApi::ApiDailyMetric.where(metric_date: @metric_date).sum(:request_count)
  end

  test "replaces existing daily metrics when rerun" do
    create_log(route_name: "pages", request_method: "GET", status_code: 200, duration_ms: 50)

    assert RecordingStudioApi::Services::AggregateApiRequestLogMetrics.call(metric_date: @metric_date)
    create_log(route_name: "pages", request_method: "GET", status_code: 200, duration_ms: 75)
    assert RecordingStudioApi::Services::AggregateApiRequestLogMetrics.call(metric_date: @metric_date)

    metric = RecordingStudioApi::ApiDailyMetric.find_by!(route_name: "pages", request_method: "GET", status_class: 2)
    assert_equal 2, metric.request_count
    assert_equal 125, metric.duration_sum_ms
    assert_equal 75, metric.duration_max_ms
  end

  private

  def create_log(route_name:, request_method:, status_code:, duration_ms:, metric_date: @metric_date, api_key: "public", rate_limited: false)
    RecordingStudioApi::ApiRequestLog.create!(
      api_key: api_key,
      route_name: route_name,
      controller_name: "RecordingStudioApi::Api::V1::ResourcesController",
      action_name: "index",
      occurred_at: metric_date.noon,
      request_id: SecureRandom.uuid,
      request_method: request_method,
      request_path: "/#{route_name || 'unknown'}",
      status_code: status_code,
      duration_ms: duration_ms,
      rate_limited: rate_limited
    )
  end
end