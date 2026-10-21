# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"

class RebuildApiRequestLogSummariesTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    RecordingStudioApi.configuration.logs_summaries_enabled = true
    RecordingStudioApi::LogsRegistration.register!
    RecordingStudioApi::ApiRequestLog.delete_all
    RecordingStudioApi::ApiRequestDaySummary.delete_all
    RecordingStudioApi::ApiRequestLatencyDaySummary.delete_all
    RecordingStudioApi::ApiDailyMetric.delete_all
    RecordingStudioApi::ApiDailyLatencyHistogramBucket.delete_all
    clear_runs!
    @day = Date.new(2026, 10, 1)
    @root_one = SecureRandom.uuid
    @root_two = SecureRandom.uuid
  end

  teardown do
    reset_recording_studio_api_configuration!
  end

  test "registers unpartitioned summaries and keeps the raw uuid primary key" do
    connection = RecordingStudioApi::ApiRequestLog.connection
    %w[
      recording_studio_api_api_request_logs
      recording_studio_api_api_request_day_summaries
      recording_studio_api_api_request_latency_day_summaries
    ].each do |table|
      relkind = connection.select_value("SELECT relkind FROM pg_class WHERE relname = #{connection.quote(table)}")
      assert_equal "r", relkind, table
    end
    log = RecordingStudioLogs.registry.log_for(RecordingStudioApi::LogsRegistration::SOURCE_MODEL)
    assert_nil log.partition_interval
    assert_equal "id", connection.primary_key("recording_studio_api_api_request_logs")
    type = connection.select_value(<<~SQL.squish)
      SELECT data_type FROM information_schema.columns
      WHERE table_name = 'recording_studio_api_api_request_logs' AND column_name = 'id'
    SQL
    assert_equal "uuid", type
    assert_equal false, RecordingStudioApi::ApiRequestLog.columns_hash.fetch("duration_ms").null
  end

  test "rebuilds counts and latency for two roots, a null root, and mixed statuses" do
    insert_log(root_recording_id: @root_one, api_key: "public", route_name: "pages", request_method: "GET", status_code: 200, duration_ms: 25)
    insert_log(root_recording_id: @root_two, api_key: "operations", route_name: "pages", request_method: "POST", status_code: 201, duration_ms: 51)
    insert_log(root_recording_id: nil, api_key: "public", route_name: "  ", request_method: "GET", status_code: 401, duration_ms: 100)
    insert_log(root_recording_id: @root_one, api_key: "public", route_name: "pages", request_method: "GET", status_code: 404, duration_ms: 250)
    insert_log(root_recording_id: @root_one, api_key: "public", route_name: "pages", request_method: "GET", status_code: 429, duration_ms: 500)
    insert_log(root_recording_id: @root_one, api_key: "public", route_name: "pages", request_method: "GET", status_code: 500, duration_ms: 10_001)
    insert_log(root_recording_id: @root_one, api_key: "public", route_name: "pages", request_method: "GET", status_code: 503, duration_ms: 90_000)
    insert_log(root_recording_id: @root_one, api_key: "public", route_name: "pages", request_method: "GET", status_code: 200, duration_ms: 12, rate_limited: true)

    RecordingStudioApi::Services::RebuildApiRequestLogSummaries.call(day: @day)

    counts = RecordingStudioApi::ApiRequestDaySummary.where(day: @day)
    assert_equal 8, counts.sum(:request_count)
    assert_equal 1, counts.where(root_recording_id: nil).sum(:request_count)
    assert_equal 1, counts.where(api_key: "operations").sum(:request_count)
    assert_equal 1, counts.where(route_name: "unknown").sum(:request_count)
    assert_equal 2, counts.where(status_code: 200).sum(:request_count)
    flagged = counts.find_by!(status_code: 200, rate_limited: true)
    assert_equal 1, flagged.request_count
    limited = counts.find_by!(status_code: 429, rate_limited: false)
    assert_equal 1, limited.request_count
    assert_equal 90_000, counts.where(status_code: 503).sum(:duration_sum_ms)

    histogram = RecordingStudioApi::ApiRequestLatencyDaySummary.where(day: @day)
    assert_equal counts.sum(:request_count), histogram.sum(:request_count)
    assert_includes histogram.distinct.pluck(:latency_bucket_ms), 30_000
    assert_equal 2, histogram.where(latency_bucket_ms: 30_000).sum(:request_count)
  end

  test "rebuild is idempotent and a sibling failure leaves the other summary" do
    insert_log(root_recording_id: @root_one, route_name: "pages", request_method: "GET", status_code: 200, duration_ms: 25)
    RecordingStudioApi::Services::RebuildApiRequestLogSummaries.call(day: @day)
    first_id = RecordingStudioApi::ApiRequestDaySummary.find_by!(day: @day).id
    RecordingStudioApi::Services::RebuildApiRequestLogSummaries.call(day: @day)
    assert_equal 1, RecordingStudioApi::ApiRequestDaySummary.where(day: @day).count
    refute_equal first_id, RecordingStudioApi::ApiRequestDaySummary.find_by!(day: @day).id

    original = RecordingStudioLogs::Aggregation::Runner.method(:call)
    RecordingStudioLogs::Aggregation::Runner.stub(:call, lambda { |definition, **kwargs|
      if definition.name == RecordingStudioApi::LogsRegistration::REQUEST_LATENCY
        RecordingStudioLogs::AggregationRun.record!(
          aggregation_name: definition.name,
          day: kwargs.fetch(:day),
          status: "failed",
          error_message: "histogram down",
          connection: kwargs.fetch(:connection)
        )
        raise "histogram down"
      end

      original.call(definition, **kwargs)
    }) do
      assert_raises(RuntimeError) do
        RecordingStudioApi::Services::RebuildApiRequestLogSummaries.call(day: @day)
      end
    end

    assert RecordingStudioApi::ApiRequestDaySummary.where(day: @day).exists?
    RecordingStudioApi.configuration.api_request_log_retention_days = 1
    RecordingStudioApi::Services::PruneApiRequestLogs.call(before: Time.utc(2026, 10, 18))
    assert RecordingStudioApi::ApiRequestLog.where(occurred_at: Time.utc(@day.year, @day.month, @day.day, 12)).exists?
  end

  test "raw prune stays blocked until both aggregations cover the day" do
    occurred_at = Time.utc(2026, 9, 1, 12)
    insert_log(root_recording_id: @root_one, route_name: "pages", request_method: "GET", status_code: 200, duration_ms: 25, occurred_at: occurred_at)
    RecordingStudioApi.configuration.api_request_log_retention_days = 1

    assert_equal 1, RecordingStudioApi::ApiRequestLog.count
    RecordingStudioApi::Services::PruneApiRequestLogs.call(before: Time.utc(2026, 10, 18))
    assert_equal 1, RecordingStudioApi::ApiRequestLog.count

    RecordingStudioApi::Services::RebuildApiRequestLogSummaries.call(day: Date.new(2026, 9, 1))
    RecordingStudioApi::Services::PruneApiRequestLogs.call(before: Time.utc(2026, 10, 18))
    assert_equal 0, RecordingStudioApi::ApiRequestLog.count
  end

  test "legacy aggregate does not write when summaries are enabled" do
    insert_log(root_recording_id: @root_one, route_name: "pages", request_method: "GET", status_code: 200, duration_ms: 25)
    refute RecordingStudioApi::Services::AggregateApiRequestLogMetrics.call(metric_date: @day)
    assert_equal 0, RecordingStudioApi::ApiDailyMetric.where(metric_date: @day).count
  end

  test "coverage mixes summary, raw, legacy, and omits gaps" do
    insert_log(root_recording_id: @root_one, route_name: "pages", request_method: "GET", status_code: 200, duration_ms: 25)
    RecordingStudioApi::Services::RebuildApiRequestLogSummaries.call(day: @day)

    raw_day = Date.new(2026, 10, 2)
    insert_log(root_recording_id: @root_one, route_name: "pages", request_method: "GET", status_code: 200, duration_ms: 40, occurred_at: Time.utc(2026, 10, 2, 12))

    legacy_day = Date.new(2026, 9, 15)
    RecordingStudioApi::ApiDailyMetric.create!(
      api_key: "public",
      metric_date: legacy_day,
      route_name: "pages",
      request_method: "GET",
      status_class: 2,
      request_count: 4,
      rate_limited_count: 0,
      client_error_count: 0,
      server_error_count: 0,
      duration_count: 4,
      duration_sum_ms: 80,
      duration_max_ms: 25
    )

    coverage = RecordingStudioApi::Services::ApiRequestLogCoverage.new
    assert_equal :summary, coverage.source_for(@day).kind
    assert_equal :raw, coverage.source_for(raw_day).kind
    assert_equal :legacy, coverage.source_for(legacy_day).kind
    assert_equal :gap, coverage.source_for(Date.new(2026, 1, 1)).kind

    rows = RecordingStudioApi::Admin::Queries::ApiMetricsQuery.call(
      start_date: Date.new(2026, 1, 1),
      end_date: raw_day
    )
    dates = rows.map(&:metric_date).uniq.sort
    assert_includes dates, @day
    assert_includes dates, raw_day
    assert_includes dates, legacy_day
    refute_includes dates, Date.new(2026, 1, 1)
  end

  test "coverage waits on the arrival watermark before treating a day as summarized" do
    travel_to Time.utc(2026, 10, 1, 12) do
      insert_log(
        root_recording_id: @root_one,
        route_name: "pages",
        request_method: "GET",
        status_code: 200,
        duration_ms: 25,
        arrived_at: Time.utc(2026, 10, 1, 12)
      )
      RecordingStudioApi::Services::RebuildApiRequestLogSummaries.call(day: @day)
    end

    coverage = RecordingStudioApi::Services::ApiRequestLogCoverage.new
    assert coverage.covered?(@day)
    assert_equal :summary, coverage.source_for(@day).kind

    insert_log(
      root_recording_id: @root_one,
      route_name: "pages",
      request_method: "GET",
      status_code: 201,
      duration_ms: 40,
      arrived_at: Time.utc(2026, 10, 1, 13)
    )

    refute coverage.covered?(@day)
    assert_equal :raw, coverage.source_for(@day).kind

    travel_to Time.utc(2026, 10, 1, 13, 1) do
      RecordingStudioApi::Services::RebuildApiRequestLogSummaries.call(day: @day)
    end

    assert coverage.covered?(@day)
    assert_equal :summary, coverage.source_for(@day).kind
  end

  test "a succeeded aggregation run without a watermark does not cover a day that still has raw rows" do
    insert_log(root_recording_id: @root_one, route_name: "pages", request_method: "GET", status_code: 200, duration_ms: 25)
    connection = RecordingStudioApi::LogsRegistration.logging_connection
    [RecordingStudioApi::LogsRegistration::REQUEST_COUNTS, RecordingStudioApi::LogsRegistration::REQUEST_LATENCY].each do |name|
      RecordingStudioLogs::AggregationRun.record!(
        aggregation_name: name,
        day: @day,
        status: "succeeded",
        connection: connection
      )
    end

    coverage = RecordingStudioApi::Services::ApiRequestLogCoverage.new
    assert RecordingStudioLogs::AggregationRun.fresh?(
      RecordingStudioApi::LogsRegistration::REQUEST_COUNTS, [@day], nil, connection: connection
    )
    assert RecordingStudioLogs::AggregationRun.fresh?(
      RecordingStudioApi::LogsRegistration::REQUEST_LATENCY, [@day], nil, connection: connection
    )
    refute coverage.covered?(@day)
    assert_equal :raw, coverage.source_for(@day).kind
  end

  test "utc midnight is the summary day under a non-utc zone" do
    Time.use_zone("Pacific/Auckland") do
      insert_log(
        root_recording_id: @root_one,
        route_name: "pages",
        request_method: "GET",
        status_code: 200,
        duration_ms: 25,
        occurred_at: Time.utc(2026, 10, 1, 0, 30)
      )
      RecordingStudioApi::Services::RebuildApiRequestLogSummaries.call(day: @day)
      assert_equal 1, RecordingStudioApi::ApiRequestDaySummary.where(day: @day).sum(:request_count)
      assert_equal 0, RecordingStudioApi::ApiRequestDaySummary.where(day: @day - 1).sum(:request_count)
    end
  end

  test "pruning summaries also removes matching run markers" do
    insert_log(root_recording_id: @root_one, route_name: "pages", request_method: "GET", status_code: 200, duration_ms: 25)
    RecordingStudioApi::Services::RebuildApiRequestLogSummaries.call(day: @day)
    RecordingStudioApi.configuration.api_daily_metric_retention_days = 1
    RecordingStudioApi::Services::PruneApiDailyMetrics.call(before: Date.new(2026, 10, 18))
    assert_equal 0, RecordingStudioApi::ApiRequestDaySummary.where(day: @day).count
    connection = RecordingStudioApi::LogsRegistration.logging_connection
    remaining = connection.select_value(<<~SQL.squish)
      SELECT COUNT(*) FROM #{connection.quote_table_name('recording_studio_logs_aggregation_runs')}
      WHERE aggregation_name = #{connection.quote(RecordingStudioApi::LogsRegistration::REQUEST_COUNTS)}
        AND day = #{connection.quote(@day)}
    SQL
    assert_equal 0, remaining.to_i
  end

  test "histogram overflow samples keep the 30000 label" do
    insert_log(root_recording_id: @root_one, route_name: "pages", request_method: "GET", status_code: 200, duration_ms: 90_000)
    RecordingStudioApi::Services::RebuildApiRequestLogSummaries.call(day: @day)
    samples = RecordingStudioApi::Admin::LatencySamples.for_day(day: @day, api_key: "public")
    assert_equal [30_000], samples
    series = RecordingStudioApi::Admin::AdminApiPerformanceScreen.latency_series_for(
      RecordingStudioApi::Admin::AdminApiPerformanceScreen.series_context(start_date: @day, end_date: @day)
    )
    assert_equal 30_000, series.first.fetch(:data).first.fetch(:y)
  end

  test "group_by on api request metrics still works after Logs loads" do
    RecordingStudioApi.configuration.logs_summaries_enabled = false
    RecordingStudioMetrics.registry.reset!
    RecordingStudioApi::Metrics.register!
    RecordingStudioApi::LogsRegistration.register!

    RecordingStudioApi::ApiDailyMetric.create!(
      api_key: "public",
      metric_date: @day,
      route_name: "pages",
      request_method: "GET",
      status_class: 5,
      request_count: 2,
      rate_limited_count: 0,
      client_error_count: 0,
      server_error_count: 2,
      duration_count: 2,
      duration_sum_ms: 40,
      duration_max_ms: 20
    )

    result = RecordingStudioMetrics.execute(
      "api_requests.server_errors_over_time",
      context: RecordingStudioMetrics::Context.new(
        system: true,
        scope: :site,
        site_authorized: true,
        timezone: "UTC"
      ),
      interval: :day,
      start_at: Time.utc(2026, 10, 1),
      end_at: Time.utc(2026, 10, 3),
      group_by: "route_name"
    )

    refute_nil result
  end

  private

  def insert_log(root_recording_id:, route_name:, request_method:, status_code:, duration_ms:, api_key: "public", rate_limited: false, occurred_at: nil, arrived_at: nil)
    RecordingStudioApi::ApiRequestLog.create!(
      api_key: api_key,
      route_name: route_name,
      controller_name: "RecordingStudioApi::Api::V1::ResourcesController",
      action_name: "index",
      occurred_at: occurred_at || Time.utc(@day.year, @day.month, @day.day, 12),
      arrived_at: arrived_at,
      request_id: SecureRandom.uuid,
      request_method: request_method,
      request_path: "/#{route_name.to_s.strip.presence || 'unknown'}",
      status_code: status_code,
      duration_ms: duration_ms,
      rate_limited: rate_limited,
      root_recording_id: root_recording_id
    )
  end

  def clear_runs!
    connection = RecordingStudioApi::LogsRegistration.logging_connection
    return unless connection.data_source_exists?("recording_studio_logs_aggregation_runs")

    connection.execute("DELETE FROM #{connection.quote_table_name('recording_studio_logs_aggregation_runs')}")
  end
end
