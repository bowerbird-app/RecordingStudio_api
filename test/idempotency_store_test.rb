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
    skip "Redis unavailable" if redis.nil? || !redis_reachable?(redis)

    key = "create-page-#{SecureRandom.hex(4)}"
    redis_key = RecordingStudioApi::IdempotencyStore.redis_key(api: "public", client_id: "client-1", key: key)
    payload = { "id" => "rec-1", "type" => "Page" }

    RecordingStudioApi::IdempotencyStore.write(
      api: "public",
      client_id: "client-1",
      key: key,
      payload: payload,
      status: "created"
    )

    cached = RecordingStudioApi::IdempotencyStore.fetch(
      api: "public",
      client_id: "client-1",
      key: key
    )

    assert_equal payload, cached.fetch("json")
    assert_equal "created", cached.fetch("status")
  ensure
    begin
      redis&.del(redis_key) if defined?(redis_key) && redis_key
    rescue StandardError
      nil
    end
  end

  private

  def redis_reachable?(redis)
    redis.ping == "PONG"
  rescue StandardError
    false
  end
end
