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
    assert_equal 1, logger.messages.length
    assert_includes warning, "[RecordingStudioApi]"
    assert_includes warning, "Rails.cache"
    assert_includes warning, "idempotency"
    assert_includes warning, "not durable"
    assert_includes warning, "ActiveSupport::Cache::MemoryStore"
    assert_includes warning, "process-local"
  end

  test "logs a warning when the fallback cache is NullStore" do
    logger = MemoryLogger.new
    Rails.cache = ActiveSupport::Cache::NullStore.new

    Rails.stub(:logger, logger) do
      RecordingStudioApi::IdempotencyStore.stub(:redis, nil) do
        write_payload(key: "null-store", payload: { "id" => "1" })
      end
    end

    warning = logger.messages.join("\n")
    assert_equal 1, logger.messages.length
    assert_includes warning, "not durable"
    assert_includes warning, "ActiveSupport::Cache::NullStore"
    assert_includes warning, "stores nothing"
  end

  test "does not log a durability warning when Redis stores the key" do
    logger = MemoryLogger.new
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    Rails.stub(:logger, logger) do
      RecordingStudioApi::IdempotencyStore.stub(:redis, AtomicRedis.new) do
        write_payload(key: "redis-quiet", payload: { "id" => "1" })
        fetch_payload(key: "redis-quiet")
      end
    end

    assert_empty logger.messages
  end

  test "fingerprint is a sha256 of method path and params with sorted keys" do
    left = RecordingStudioApi::IdempotencyStore.fingerprint(
      method: "post",
      path: "folders",
      params: { name: "A", parent_id: "1", meta: { b: 1, a: 2 } }
    )
    right = RecordingStudioApi::IdempotencyStore.fingerprint(
      method: "POST",
      path: "folders",
      params: { "parent_id" => "1", "meta" => { "a" => 2, "b" => 1 }, "name" => "A" }
    )
    different_body = RecordingStudioApi::IdempotencyStore.fingerprint(
      method: "POST",
      path: "folders",
      params: { "name" => "B", "parent_id" => "1" }
    )
    different_path = RecordingStudioApi::IdempotencyStore.fingerprint(
      method: "POST",
      path: "pages",
      params: { "name" => "A", "parent_id" => "1", "meta" => { "a" => 2, "b" => 1 } }
    )

    assert_equal 64, left.length
    assert_equal left, right
    refute_equal left, different_body
    refute_equal left, different_path
    refute_equal(
      RecordingStudioApi::IdempotencyStore.fingerprint(method: "POST", path: "folders", params: { tags: %w[a b] }),
      RecordingStudioApi::IdempotencyStore.fingerprint(method: "POST", path: "folders", params: { tags: %w[b a] })
    )
  end

  test "same fingerprint replays and a different fingerprint raises without replacing the payload" do
    fingerprint = RecordingStudioApi::IdempotencyStore.fingerprint(
      method: "POST", path: "folders", params: { "name" => "A" }
    )
    other = RecordingStudioApi::IdempotencyStore.fingerprint(
      method: "POST", path: "folders", params: { "name" => "B" }
    )

    RecordingStudioApi::IdempotencyStore.stub(:redis, nil) do
      write_payload(key: "fp", payload: { "id" => "first" }, fingerprint: fingerprint)

      cached = fetch_payload(key: "fp", fingerprint: fingerprint)
      assert_equal "first", cached.fetch("json").fetch("id")
      assert_equal fingerprint, cached.fetch("fingerprint")

      error = assert_raises(RecordingStudioApi::IdempotencyKeyMismatchError) do
        fetch_payload(key: "fp", fingerprint: other)
      end
      assert_equal "idempotency_key_reused", error.code
      assert_equal "Idempotency key already used with different parameters", error.message
      assert_kind_of RecordingStudioApi::Error, error

      write_payload(key: "fp", payload: { "id" => "second" }, fingerprint: other)
      assert_equal "first", fetch_payload(key: "fp", fingerprint: fingerprint).fetch("json").fetch("id")
    end
  end

  test "a stored entry without a fingerprint still replays" do
    fingerprint = RecordingStudioApi::IdempotencyStore.fingerprint(
      method: "POST", path: "folders", params: { "name" => "Later" }
    )

    RecordingStudioApi::IdempotencyStore.stub(:redis, nil) do
      write_payload(key: "legacy", payload: { "id" => "legacy" })

      cached = fetch_payload(key: "legacy", fingerprint: fingerprint)
      assert_equal "legacy", cached.fetch("json").fetch("id")
      assert_nil cached["fingerprint"]
    end
  end

  test "the same key on another client or named API does not replay or mismatch" do
    fingerprint = RecordingStudioApi::IdempotencyStore.fingerprint(
      method: "POST", path: "folders", params: { "name" => "A" }
    )
    other = RecordingStudioApi::IdempotencyStore.fingerprint(
      method: "POST", path: "folders", params: { "name" => "B" }
    )

    RecordingStudioApi::IdempotencyStore.stub(:redis, AtomicRedis.new) do
      write_payload(key: "isolated", payload: { "id" => "public-client" }, fingerprint: fingerprint)

      assert_nil fetch_payload(key: "isolated", api: "operations", fingerprint: other)
      assert_nil fetch_payload(key: "isolated", client_id: "client-2", fingerprint: other)
      assert_equal "public-client", fetch_payload(key: "isolated", fingerprint: fingerprint).fetch("json").fetch("id")
    end
  end

  test "a fingerprint mismatch on the Rails.cache fallback does not replay" do
    fingerprint = RecordingStudioApi::IdempotencyStore.fingerprint(method: "POST", path: "folders", params: { "name" => "A" })
    other = RecordingStudioApi::IdempotencyStore.fingerprint(method: "POST", path: "folders", params: { "name" => "B" })

    RecordingStudioApi::IdempotencyStore.stub(:redis, FailingRedis.new) do
      write_payload(key: "fallback-mismatch", payload: { "id" => "cached" }, fingerprint: fingerprint)

      assert_raises(RecordingStudioApi::IdempotencyKeyMismatchError) do
        fetch_payload(key: "fallback-mismatch", fingerprint: other)
      end
      assert_equal "cached", fetch_payload(key: "fallback-mismatch", fingerprint: fingerprint).fetch("json").fetch("id")
    end
  end

  test "NullStore fallback stores nothing so a fingerprint does not raise" do
    Rails.cache = ActiveSupport::Cache::NullStore.new
    fingerprint = RecordingStudioApi::IdempotencyStore.fingerprint(method: "POST", path: "folders", params: { "name" => "A" })

    RecordingStudioApi::IdempotencyStore.stub(:redis, nil) do
      write_payload(key: "null-fingerprint", payload: { "id" => "gone" }, fingerprint: fingerprint)
      assert_nil fetch_payload(key: "null-fingerprint", fingerprint: fingerprint)
    end
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

  def write_payload(key:, payload:, api: "public", client_id: "client-1", fingerprint: nil)
    RecordingStudioApi::IdempotencyStore.write(
      api: api,
      client_id: client_id,
      key: key,
      payload: payload,
      status: "created",
      fingerprint: fingerprint
    )
  end

  def fetch_payload(key:, api: "public", client_id: "client-1", fingerprint: nil)
    RecordingStudioApi::IdempotencyStore.fetch(
      api: api,
      client_id: client_id,
      key: key,
      fingerprint: fingerprint
    )
  end

  def redis_reachable?(redis)
    redis.ping == "PONG"
  rescue StandardError
    false
  end
end
