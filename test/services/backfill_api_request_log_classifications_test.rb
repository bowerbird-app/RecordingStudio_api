# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"

class BackfillApiRequestLogClassificationsTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    RecordingStudioApi::ApiRequestLog.delete_all
  end

  test "backfills arrival bucket and blank names in bounded batches" do
    occurred_at = Time.utc(2026, 9, 1, 8, 0, 0)
    created_at = Time.utc(2026, 9, 1, 8, 0, 5)
    first_id, second_id = Array.new(2) { SecureRandom.uuid }

    RecordingStudioApi::ApiRequestLog.insert_all(
      [
        historical_row(id: first_id, occurred_at: occurred_at, created_at: created_at, duration_ms: 10_001, api_key: " ", route_name: nil),
        historical_row(id: second_id, occurred_at: occurred_at + 1.second, created_at: created_at + 1.second, duration_ms: 25, api_key: "", route_name: "")
      ]
    )

    backfill = RecordingStudioApi::Services::BackfillApiRequestLogClassifications.new(batch_size: 1)
    updated_first = backfill.process_batch
    assert_equal 1, updated_first

    first = RecordingStudioApi::ApiRequestLog.find(first_id)
    assert_equal created_at.to_i, first.arrived_at.to_i
    refute_equal occurred_at.to_i, first.arrived_at.to_i
    assert_equal 30_000, first.latency_bucket_ms
    assert_equal "public", first.api_key
    assert_equal "unknown", first.route_name

    second = RecordingStudioApi::ApiRequestLog.find(second_id)
    assert_nil second.arrived_at
    assert_nil second.latency_bucket_ms

    updated_second = backfill.process_batch
    assert_equal 1, updated_second
    second.reload
    assert_equal 25, second.latency_bucket_ms
    assert_equal "public", second.api_key
    assert_equal "unknown", second.route_name

    assert_equal 0, backfill.process_batch
    assert_equal 0, RecordingStudioApi::Services::BackfillApiRequestLogClassifications.call(batch_size: 1)
  end

  test "raw table stays unpartitioned with a uuid primary key" do
    connection = RecordingStudioApi::ApiRequestLog.connection
    table = RecordingStudioApi::ApiRequestLog.table_name
    columns = connection.columns(table).index_by(&:name)
    assert columns.key?("arrived_at")
    assert columns.key?("latency_bucket_ms")
    assert_equal "clock_timestamp()", columns.fetch("arrived_at").default_function
    relkind = connection.select_value(
      "SELECT relkind FROM pg_class WHERE relname = #{connection.quote(table)}"
    )
    assert_equal "r", relkind
    assert_equal "id", connection.primary_key(table)
    type = connection.select_value(<<~SQL.squish)
      SELECT data_type
      FROM information_schema.columns
      WHERE table_name = #{connection.quote(table)}
        AND column_name = 'id'
    SQL
    assert_equal "uuid", type
  end

  private

  def historical_row(id:, occurred_at:, created_at:, duration_ms:, api_key:, route_name:)
    {
      "id" => id,
      "occurred_at" => occurred_at,
      "created_at" => created_at,
      "updated_at" => created_at,
      "request_id" => SecureRandom.uuid,
      "request_method" => "GET",
      "request_path" => "/recording_studio_api/api/v1/pages",
      "route_name" => route_name,
      "controller_name" => "RecordingStudioApi::Api::V1::ResourcesController",
      "action_name" => "index",
      "status_code" => 200,
      "duration_ms" => duration_ms,
      "rate_limited" => false,
      "api_key" => api_key,
      "request_params" => {},
      "arrived_at" => nil,
      "latency_bucket_ms" => nil
    }
  end
end
