# frozen_string_literal: true

require "redis"
require_relative "support/api_dummy_helpers"

class IdempotencyStoreTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  class MemoryLogger
    attr_reader :messages

    def initialize
      @messages = []
    end

    def warn(message)
      messages << message
    end
  end

  class AtomicRedis
    def initialize
      @store = {}
      @mutex = Mutex.new
    end

    def get(key)
      @mutex.synchronize { @store[key] }
    end

    def set(key, value, nx: false, **) # rubocop:disable Naming/MethodParameterName
      @mutex.synchronize do
        return nil if nx && @store.key?(key)

        @store[key] = value
        "OK"
      end
    end
  end

  class FailingRedis
    def get(*)
      raise Redis::CannotConnectError, "Connection refused"
    end

    def set(*)
      raise Redis::CannotConnectError, "Connection refused"
    end
  end

  setup do
    reset_recording_studio_api_configuration!
    @previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    RecordingStudioApi::IdempotencyStore.reset_fallback_notice!
  end

  teardown do
    Rails.cache = @previous_cache
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

  test "round-trips a create payload through Rails.cache when Redis is missing" do
    payload = { "id" => "rec-1", "type" => "Folder" }

    RecordingStudioApi::IdempotencyStore.stub(:redis, nil) do
      write_payload(key: "no-redis", payload: payload)
      cached = fetch_payload(key: "no-redis")

      assert_equal payload, cached.fetch("json")
      assert_equal "created", cached.fetch("status")
    end
  end

  test "a second write with the same key keeps the first payload when Redis is missing" do
    RecordingStudioApi::IdempotencyStore.stub(:redis, nil) do
      write_payload(key: "nx-cache", payload: { "id" => "first" })
      write_payload(key: "nx-cache", payload: { "id" => "second" })

      assert_equal "first", fetch_payload(key: "nx-cache").fetch("json").fetch("id")
    end
  end

  test "a second write with the same key keeps the first payload on Redis SET NX" do
    redis = AtomicRedis.new

    RecordingStudioApi::IdempotencyStore.stub(:redis, redis) do
      write_payload(key: "nx-redis", payload: { "id" => "first" })
      write_payload(key: "nx-redis", payload: { "id" => "second" })

      assert_equal "first", fetch_payload(key: "nx-redis").fetch("json").fetch("id")
    end
  end

  test "falls back to Rails.cache when Redis raises BaseError" do
    payload = { "id" => "from-cache", "type" => "Folder" }

    RecordingStudioApi::IdempotencyStore.stub(:redis, FailingRedis.new) do
      write_payload(key: "redis-error", payload: payload)
      cached = fetch_payload(key: "redis-error")

      assert_equal payload, cached.fetch("json")
    end
  end

  test "logs a warning when falling back to Rails.cache" do
    logger = MemoryLogger.new

    Rails.stub(:logger, logger) do
      RecordingStudioApi::IdempotencyStore.stub(:redis, nil) do
        write_payload(key: "warn", payload: { "id" => "1" })
        fetch_payload(key: "warn")
      end
    end

    warning = logger.messages.join("\n")
    assert_includes warning, "[RecordingStudioApi]"
    assert_includes warning, "Rails.cache"
    assert_includes warning, "idempotency"
  end

  test "concurrent writes store only one payload" do
    RecordingStudioApi::IdempotencyStore.stub(:redis, nil) do
      gate = Queue.new
      threads = %w[alpha beta].map do |id|
        Thread.new do
          gate.pop
          write_payload(key: "race", payload: { "id" => id })
        end
      end

      2.times { gate << true }
      threads.each(&:join)

      stored_id = fetch_payload(key: "race").fetch("json").fetch("id")
      assert_includes %w[alpha beta], stored_id
    end
  end

  private

  def write_payload(key:, payload:)
    RecordingStudioApi::IdempotencyStore.write(
      api: "public",
      client_id: "client-1",
      key: key,
      payload: payload,
      status: "created"
    )
  end

  def fetch_payload(key:)
    RecordingStudioApi::IdempotencyStore.fetch(
      api: "public",
      client_id: "client-1",
      key: key
    )
  end

  def redis_reachable?(redis)
    redis.ping == "PONG"
  rescue StandardError
    false
  end
end
