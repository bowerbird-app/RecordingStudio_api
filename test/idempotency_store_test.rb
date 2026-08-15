# frozen_string_literal: true

require_relative "support/api_dummy_helpers"

class IdempotencyStoreTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
  end

  teardown do
    reset_recording_studio_api_configuration!
  end

  test "returns nil when key or client is blank" do
    assert_nil RecordingStudioApi::IdempotencyStore.fetch(api: "public", client_id: nil, key: "abc")
    assert_nil RecordingStudioApi::IdempotencyStore.fetch(api: "public", client_id: "1", key: "")
  end

  test "round-trips payloads when redis is available" do
    redis = RecordingStudioApi::Concerns::RateLimiting.redis_client
    skip "Redis unavailable" if redis.nil?

    begin
      redis.ping
    rescue StandardError
      skip "Redis unavailable"
    end

    payload = { "id" => "rec-1", "type" => "Page" }
    RecordingStudioApi::IdempotencyStore.write(
      api: "public",
      client_id: "client-1",
      key: "create-page-1",
      payload: payload,
      status: "created"
    )

    cached = RecordingStudioApi::IdempotencyStore.fetch(
      api: "public",
      client_id: "client-1",
      key: "create-page-1"
    )

    assert_equal payload, cached.fetch("json")
    assert_equal "created", cached.fetch("status")
  ensure
    redis&.del(
      RecordingStudioApi::IdempotencyStore.redis_key(api: "public", client_id: "client-1", key: "create-page-1")
    )
  end
end
