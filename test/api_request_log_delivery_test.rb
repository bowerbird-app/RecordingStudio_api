# frozen_string_literal: true

require_relative "support/api_dummy_helpers"
require "active_job/test_helper"

class ApiRequestLogDeliveryTest < ActiveSupport::TestCase
  include ApiDummyHelpers
  include ActiveJob::TestHelper

  setup do
    reset_recording_studio_api_configuration!
    RecordingStudioApi::ApiRequestLog.delete_all
    RecordingStudioApi::ApiRequestLogBatch.clear!
    clear_enqueued_jobs
  end

  teardown do
    clear_enqueued_jobs
    RecordingStudioApi::ApiRequestLogBatch.clear!
    reset_recording_studio_api_configuration!
  end

  test "sync delivery writes immediately" do
    RecordingStudioApi.configuration.api_request_logging_delivery = "sync"

    assert_difference -> { RecordingStudioApi::ApiRequestLog.count }, 1 do
      RecordingStudioApi::ApiRequestLogDelivery.deliver(sample_payload)
    end
  end

  test "async delivery enqueues a write job" do
    RecordingStudioApi.configuration.api_request_logging_delivery = "async"

    assert_enqueued_with(job: RecordingStudioApi::WriteApiRequestLogsJob) do
      RecordingStudioApi::ApiRequestLogDelivery.deliver(sample_payload)
    end
    assert_equal 0, RecordingStudioApi::ApiRequestLog.count
  end

  test "batched delivery flushes through active job" do
    RecordingStudioApi.configuration.api_request_logging_delivery = "batched"
    RecordingStudioApi.configuration.api_request_logging_batch_size = 2

    RecordingStudioApi::ApiRequestLogDelivery.deliver(sample_payload(request_id: "one"))
    assert_equal 1, RecordingStudioApi::ApiRequestLogBatch.buffer_size
    assert_no_enqueued_jobs

    assert_enqueued_with(job: RecordingStudioApi::WriteApiRequestLogsJob) do
      RecordingStudioApi::ApiRequestLogDelivery.deliver(sample_payload(request_id: "two"))
    end
    assert_equal 0, RecordingStudioApi::ApiRequestLogBatch.buffer_size
  end

  test "write job inserts a batch of payloads" do
    payloads = [
      sample_payload(request_id: "batch-1").transform_keys(&:to_s).tap { |row| row["occurred_at"] = Time.current.iso8601(6) },
      sample_payload(request_id: "batch-2").transform_keys(&:to_s).tap { |row| row["occurred_at"] = Time.current.iso8601(6) }
    ]

    assert_difference -> { RecordingStudioApi::ApiRequestLog.count }, 2 do
      RecordingStudioApi::WriteApiRequestLogsJob.perform_now(payloads)
    end

    rows = RecordingStudioApi::ApiRequestLog.order(:request_id)
    assert(rows.all? { |row| row.arrived_at.present? })
    assert_equal [25, 25], rows.map(&:latency_bucket_ms)
  end

  test "old queued payload without new fields still classifies on write" do
    payload = sample_payload(request_id: "legacy-queue", duration_ms: 10_001, api_key: " ", route_name: nil)
    payload.delete(:api_key)
    serialized = payload.transform_keys(&:to_s)
    serialized["occurred_at"] = payload[:occurred_at].iso8601(6)

    RecordingStudioApi::WriteApiRequestLogsJob.perform_now([serialized])

    row = RecordingStudioApi::ApiRequestLog.find_by!(request_id: "legacy-queue")
    assert_equal "public", row.api_key
    assert_equal "unknown", row.route_name
    assert_equal 30_000, row.latency_bucket_ms
    assert_not_nil row.arrived_at
  end

  test "enqueue failure writes classified rows without raising to the caller" do
    RecordingStudioApi.configuration.api_request_logging_delivery = "async"
    RecordingStudioApi::WriteApiRequestLogsJob.stub(:perform_later, proc { raise "queue down" }) do
      RecordingStudioApi::ApiRequestLogDelivery.deliver(sample_payload(request_id: "fallback", duration_ms: 51, api_key: ""))
    end

    row = RecordingStudioApi::ApiRequestLog.find_by!(request_id: "fallback")
    assert_equal 100, row.latency_bucket_ms
    assert_equal "public", row.api_key
  end

  test "enqueue fallback isolates a write failure from the caller" do
    RecordingStudioApi.configuration.api_request_logging_delivery = "async"
    RecordingStudioApi::WriteApiRequestLogsJob.stub(:perform_later, proc { raise "queue down" }) do
      RecordingStudioApi::ApiRequestLog.stub(:write_payloads!, proc { raise "insert failed" }) do
        RecordingStudioApi::ApiRequestLogDelivery.deliver(sample_payload(request_id: "isolated"))
      end
    end

    assert_nil RecordingStudioApi::ApiRequestLog.find_by(request_id: "isolated")
  end

  test "new inserts use clock_timestamp rather than the transaction start" do
    connection = RecordingStudioApi::ApiRequestLog.connection
    table = RecordingStudioApi::ApiRequestLog.quoted_table_name
    row = nil
    RecordingStudioApi::ApiRequestLog.transaction do
      connection.execute("SELECT pg_sleep(0.05)")
      RecordingStudioApi::ApiRequestLog.write_payloads!([sample_payload(request_id: "clock")])
      row = RecordingStudioApi::ApiRequestLog.find_by!(request_id: "clock")
      lag_from_transaction = connection.select_value(
        "SELECT EXTRACT(EPOCH FROM (arrived_at - now())) FROM #{table} WHERE id = #{connection.quote(row.id)}"
      ).to_f
      lag_from_clock = connection.select_value(
        "SELECT EXTRACT(EPOCH FROM (clock_timestamp() - arrived_at)) FROM #{table} WHERE id = #{connection.quote(row.id)}"
      ).to_f
      assert_operator lag_from_transaction, :>, 0.04
      assert_operator lag_from_clock.abs, :<, 0.05
    end
    assert_not_nil row.arrived_at
  end

  test "request logs use the api_logging database when it is configured" do
    config = RecordingStudioApi::ApiRequestLog.connection_db_config
    assert_equal "api_logging", config.name
  end

  private

  def sample_payload(request_id: SecureRandom.uuid, duration_ms: 12, api_key: "public", route_name: "pages")
    {
      occurred_at: Time.current,
      request_id: request_id,
      request_method: "GET",
      request_path: "/recording_studio_api/api/v1/pages",
      route_name: route_name,
      controller_name: "RecordingStudioApi::Api::V1::ResourcesController",
      action_name: "index",
      status_code: 200,
      duration_ms: duration_ms,
      rate_limited: false,
      api_key: api_key,
      api_client_id: nil,
      api_credential_id: nil,
      access_recording_id: nil,
      root_recording_id: nil,
      remote_ip: "127.0.0.1",
      user_agent: "test",
      error_class: nil,
      error_message: nil,
      request_params: {}
    }
  end
end
