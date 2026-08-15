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
  end

  private

  def sample_payload(request_id: SecureRandom.uuid)
    {
      occurred_at: Time.current,
      request_id: request_id,
      request_method: "GET",
      request_path: "/recording_studio_api/api/v1/pages",
      route_name: "pages",
      controller_name: "RecordingStudioApi::Api::V1::ResourcesController",
      action_name: "index",
      status_code: 200,
      duration_ms: 12,
      rate_limited: false,
      api_key: "public",
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
