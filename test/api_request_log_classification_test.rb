# frozen_string_literal: true

require "test_helper"

class ApiRequestLogClassificationTest < Minitest::Test
  def test_bucket_boundaries_and_overflow_label
    assert_equal 25, RecordingStudioApi::ApiRequestLogClassification.bucket_ms(0)
    assert_equal 25, RecordingStudioApi::ApiRequestLogClassification.bucket_ms(25)
    assert_equal 50, RecordingStudioApi::ApiRequestLogClassification.bucket_ms(26)
    assert_equal 50, RecordingStudioApi::ApiRequestLogClassification.bucket_ms(50)
    assert_equal 100, RecordingStudioApi::ApiRequestLogClassification.bucket_ms(51)
    assert_equal 10_000, RecordingStudioApi::ApiRequestLogClassification.bucket_ms(10_000)
    assert_equal 30_000, RecordingStudioApi::ApiRequestLogClassification.bucket_ms(10_001)
    assert_equal 30_000, RecordingStudioApi::ApiRequestLogClassification.bucket_ms(30_000)
    assert_equal 30_000, RecordingStudioApi::ApiRequestLogClassification.bucket_ms(90_000)
    assert_nil RecordingStudioApi::ApiRequestLogClassification.bucket_ms(nil)
  end

  def test_blank_api_name_and_route_normalize
    row = RecordingStudioApi::ApiRequestLogClassification.attributes_for_insert(
      occurred_at: Time.utc(2026, 10, 1, 12),
      request_method: "GET",
      request_path: "/recording_studio_api/api/v1/pages",
      route_name: "  ",
      status_code: 200,
      duration_ms: 12,
      api_key: nil
    )

    assert_equal "public", row.fetch("api_key")
    assert_equal "unknown", row.fetch("route_name")
    assert_equal 25, row.fetch("latency_bucket_ms")
    refute row.key?("arrived_at")
  end

  def test_old_queued_payload_without_new_fields_classifies
    occurred_at = Time.utc(2026, 10, 1, 12, 0, 0)
    row = RecordingStudioApi::ApiRequestLogClassification.attributes_for_insert(
      "occurred_at" => occurred_at.iso8601(6),
      "request_id" => "queued-old",
      "request_method" => "POST",
      "request_path" => "/recording_studio_api/api/v1/pages",
      "route_name" => "pages",
      "controller_name" => "RecordingStudioApi::Api::V1::ResourcesController",
      "action_name" => "create",
      "status_code" => 201,
      "duration_ms" => 250,
      "rate_limited" => false,
      "api_key" => "operations",
      "request_params" => {}
    )

    assert_equal occurred_at, row.fetch("occurred_at")
    assert_equal 250, row.fetch("latency_bucket_ms")
    assert_equal "operations", row.fetch("api_key")
    assert_equal "pages", row.fetch("route_name")
    refute row.key?("arrived_at")
  end
end
