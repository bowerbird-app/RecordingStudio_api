# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "../test_helper"
require_relative "../dummy/config/environment"
require "active_job/test_helper"

class MaintainApiMetricsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    travel_to Time.zone.local(2026, 8, 15, 12, 0, 0)
    RecordingStudioApi.configuration.api_request_log_retention_days = 30
    RecordingStudioApi.configuration.api_daily_metric_retention_days = 90
    RecordingStudioApi::ApiRequestLog.delete_all
    RecordingStudioApi::ApiDailyMetric.delete_all
    RecordingStudioApi::ApiDailyLatencyHistogramBucket.delete_all
    clear_enqueued_jobs
  end

  teardown do
    travel_back
    RecordingStudioApi.configuration.api_request_log_retention_days = 30
    RecordingStudioApi.configuration.api_daily_metric_retention_days = nil
    clear_enqueued_jobs
  end

  test "prunes request logs older than retention and keeps newer rows" do
    old_log = create_log(occurred_at: 31.days.ago)
    recent_log = create_log(occurred_at: 2.days.ago)

    deleted = RecordingStudioApi::Services::PruneApiRequestLogs.call

    assert_equal 1, deleted
    assert_nil RecordingStudioApi::ApiRequestLog.find_by(id: old_log.id)
    assert RecordingStudioApi::ApiRequestLog.exists?(recent_log.id)
  end

  test "does not prune daily metrics when retention is unset" do
    RecordingStudioApi.configuration.api_daily_metric_retention_days = nil
    create_daily_metric(metric_date: 400.days.ago.to_date)

    assert_equal 0, RecordingStudioApi::Services::PruneApiDailyMetrics.call
    assert_equal 1, RecordingStudioApi::ApiDailyMetric.count
  end

  test "prunes daily metrics and latency buckets older than retention" do
    old_metric = create_daily_metric(metric_date: 91.days.ago.to_date)
    recent_metric = create_daily_metric(metric_date: 10.days.ago.to_date)
    old_bucket = create_latency_bucket(metric_date: 91.days.ago.to_date)
    recent_bucket = create_latency_bucket(metric_date: 10.days.ago.to_date)

    deleted = RecordingStudioApi::Services::PruneApiDailyMetrics.call

    assert_equal 2, deleted
    assert_nil RecordingStudioApi::ApiDailyMetric.find_by(id: old_metric.id)
    assert_nil RecordingStudioApi::ApiDailyLatencyHistogramBucket.find_by(id: old_bucket.id)
    assert RecordingStudioApi::ApiDailyMetric.exists?(recent_metric.id)
    assert RecordingStudioApi::ApiDailyLatencyHistogramBucket.exists?(recent_bucket.id)
  end

  test "maintain aggregates recent days then prunes logs and metrics" do
    create_log(occurred_at: 1.day.ago.change(hour: 12), route_name: "pages", status_code: 200, duration_ms: 40)
    create_log(occurred_at: 31.days.ago, route_name: "pages", status_code: 200, duration_ms: 40)
    create_daily_metric(metric_date: 91.days.ago.to_date)
    create_latency_bucket(metric_date: 91.days.ago.to_date)

    result = RecordingStudioApi::Services::MaintainApiMetrics.call(lookback_days: 2)

    assert_includes result[:aggregated_dates], Date.current - 1.day
    assert_operator result[:pruned_request_logs], :>=, 1
    assert_operator result[:pruned_daily_metrics], :>=, 2
    assert RecordingStudioApi::ApiDailyMetric.exists?(metric_date: Date.current - 1.day, route_name: "pages")
    assert_equal 0, RecordingStudioApi::ApiRequestLog.where("occurred_at < ?", 30.days.ago).count
  end

  test "MaintainApiMetricsJob enqueues and performs maintenance" do
    create_log(occurred_at: 31.days.ago)

    assert_enqueued_with(job: RecordingStudioApi::MaintainApiMetricsJob) do
      RecordingStudioApi::MaintainApiMetricsJob.perform_later
    end

    perform_enqueued_jobs
    assert_equal 0, RecordingStudioApi::ApiRequestLog.where("occurred_at < ?", 30.days.ago).count
  end

  private

  def create_log(occurred_at:, route_name: "pages", status_code: 200, duration_ms: 25)
    RecordingStudioApi::ApiRequestLog.create!(
      api_key: "public",
      route_name: route_name,
      controller_name: "RecordingStudioApi::Api::V1::ResourcesController",
      action_name: "index",
      occurred_at: occurred_at,
      request_id: SecureRandom.uuid,
      request_method: "GET",
      request_path: "/#{route_name}",
      status_code: status_code,
      duration_ms: duration_ms,
      rate_limited: false
    )
  end

  def create_daily_metric(metric_date:)
    RecordingStudioApi::ApiDailyMetric.create!(
      api_key: "public",
      metric_date: metric_date,
      route_name: "pages",
      controller_name: "RecordingStudioApi::Api::V1::ResourcesController",
      action_name: "index",
      request_method: "GET",
      status_class: 2,
      request_count: 1,
      rate_limited_count: 0,
      client_error_count: 0,
      server_error_count: 0,
      duration_count: 1,
      duration_sum_ms: 25,
      duration_max_ms: 25
    )
  end

  def create_latency_bucket(metric_date:)
    RecordingStudioApi::ApiDailyLatencyHistogramBucket.create!(
      api_key: "public",
      metric_date: metric_date,
      route_name: "pages",
      request_method: "GET",
      status_class: 2,
      upper_bound_ms: 50,
      request_count: 1
    )
  end
end
