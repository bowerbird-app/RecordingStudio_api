# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"

class LogsRegistrationTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    RecordingStudioApi::LogsRegistration.register!
  end

  teardown do
    reset_recording_studio_api_configuration!
  end

  test "registers unpartitioned request logs with a root column and indefinite retention" do
    connection = RecordingStudioApi::ApiRequestLog.connection
    assert_equal "r", connection.select_value(
      "SELECT relkind FROM pg_class WHERE relname = #{connection.quote('recording_studio_api_api_request_logs')}"
    )
    %w[
      recording_studio_api_api_request_day_summaries
      recording_studio_api_api_request_latency_day_summaries
      recording_studio_api_api_request_day_metric_rollups
    ].each do |name|
      relkind = connection.select_value("SELECT relkind FROM pg_class WHERE relname = #{connection.quote(name)}")
      assert_nil relkind, name
    end

    log = RecordingStudioLogs.registry.log_for(RecordingStudioApi::LogsRegistration::SOURCE_MODEL)
    assert_nil log.partition_interval
    assert_equal :root_recording_id, log.root_column
    assert_equal :indefinite, log.retention
    assert_equal "id", connection.primary_key("recording_studio_api_api_request_logs")
    type = connection.select_value(<<~SQL.squish)
      SELECT data_type FROM information_schema.columns
      WHERE table_name = 'recording_studio_api_api_request_logs' AND column_name = 'id'
    SQL
    assert_equal "uuid", type
  end

  test "does not register Logs aggregations" do
    names = RecordingStudioLogs.registry.aggregations.map(&:name)
    refute_includes names, "api/request_counts"
    refute_includes names, "api/request_latency"
    api_aggregations = RecordingStudioLogs.registry.aggregations_for(
      RecordingStudioLogs.registry.log_for(RecordingStudioApi::LogsRegistration::SOURCE_MODEL)
    )
    assert_empty api_aggregations
  end

  test "setting logs_summaries_enabled does not stop legacy aggregate or prune" do
    RecordingStudioApi.configuration.logs_summaries_enabled = true
    day = Date.new(2026, 10, 1)
    RecordingStudioApi::ApiRequestLog.delete_all
    RecordingStudioApi::ApiDailyMetric.delete_all
    RecordingStudioApi::ApiDailyLatencyHistogramBucket.delete_all

    RecordingStudioApi::ApiRequestLog.create!(
      api_key: "public",
      route_name: "pages",
      controller_name: "RecordingStudioApi::Api::V1::ResourcesController",
      action_name: "index",
      occurred_at: Time.utc(2026, 10, 1, 12),
      request_id: SecureRandom.uuid,
      request_method: "GET",
      request_path: "/pages",
      status_code: 200,
      duration_ms: 25,
      rate_limited: false
    )
    old_log = RecordingStudioApi::ApiRequestLog.create!(
      api_key: "public",
      route_name: "pages",
      controller_name: "RecordingStudioApi::Api::V1::ResourcesController",
      action_name: "index",
      occurred_at: Time.utc(2026, 8, 1, 12),
      request_id: SecureRandom.uuid,
      request_method: "GET",
      request_path: "/pages",
      status_code: 200,
      duration_ms: 25,
      rate_limited: false
    )

    assert RecordingStudioApi::Services::AggregateApiRequestLogMetrics.call(metric_date: day)
    assert RecordingStudioApi::ApiDailyMetric.exists?(metric_date: day, route_name: "pages")

    deleted = RecordingStudioApi::Services::PruneApiRequestLogs.call(before: Time.utc(2026, 9, 1))
    assert_equal 1, deleted
    assert_nil RecordingStudioApi::ApiRequestLog.find_by(id: old_log.id)
  end
end
