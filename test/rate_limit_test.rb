# frozen_string_literal: true

require "test_helper"
require_relative "../app/controllers/recording_studio_api/concerns/rate_limiting"

class RateLimitTest < ActiveSupport::TestCase
  class MemoryRedis
    attr_reader :eval_calls, :expire_calls

    def initialize
      @counts = Hash.new(0)
      @ttl = {}
      @eval_calls = []
      @expire_calls = []
    end

    def incr(key)
      @counts[key] += 1
    end

    def expire(key, period)
      expire_calls << [key, period]
      @ttl[key] = period
    end

    def ttl(key)
      @ttl.fetch(key, -1)
    end

    def eval(script, keys:, argv:)
      eval_calls << { script: script, keys: keys, argv: argv }
      key = keys.fetch(0)
      count = incr(key)
      current_ttl = ttl(key)
      if count == 1 || current_ttl.to_i.negative?
        expire(key, argv.fetch(0))
        current_ttl = ttl(key)
      end
      [count, current_ttl]
    end
  end

  class IncrOnlyRedis < MemoryRedis
    undef_method :eval
  end

  class BrokenRedis < MemoryRedis
    def eval(*)
      raise "offline"
    end
  end

  def setup
    @original_configuration = RecordingStudioApi.instance_variable_get(:@configuration)
    RecordingStudioApi.instance_variable_set(:@configuration, RecordingStudioApi::Configuration.new)
  end

  def teardown
    RecordingStudioApi.instance_variable_set(:@configuration, @original_configuration)
  end

  test "key uses namespace kind identifier and window" do
    assert_equal(
      "recording_studio_api:api_read:credential:cred-1:42",
      RecordingStudioApi::RateLimit.key(kind: :read, identifier: "credential:cred-1", window: 42)
    )
    assert_equal(
      "recording_studio_api:api_write:client:client-7:42",
      RecordingStudioApi::RateLimit.key(kind: "write", identifier: "client:client-7", window: 42)
    )
    assert_equal(
      "recording_studio_api:oauth:ip:203.0.113.9:7",
      RecordingStudioApi::RateLimit.key(kind: "oauth", identifier: "ip:203.0.113.9", window: 7)
    )
    assert_equal(
      "recording_studio_api:api_pre_auth:ip:203.0.113.9:7",
      RecordingStudioApi::RateLimit.key(kind: "api_pre_auth", identifier: "ip:203.0.113.9", window: 7)
    )
  end

  test "key applies the configured namespace and a named api" do
    RecordingStudioApi.configuration.rate_limit_redis_namespace = "custom_ns"

    assert_equal(
      "custom_ns:api_read:actor:User:9:3",
      RecordingStudioApi::RateLimit.key(kind: :read, identifier: "actor:User:9", window: 3)
    )
    assert_equal(
      "custom_ns:operations:api_write:actor:User:9:3",
      RecordingStudioApi::RateLimit.key(kind: :write, identifier: "actor:User:9", window: 3, api: :operations)
    )
    assert_equal(
      "already:scoped:api_read:credential:1:3",
      RecordingStudioApi::RateLimit.key(
        kind: :read,
        identifier: "credential:1",
        window: 3,
        namespace: "already:scoped",
        api: :operations
      )
    )
  end

  test "check increments against the configured read limit and reports the window" do
    RecordingStudioApi.configuration.rate_limit_api_read_requests = 2
    RecordingStudioApi.configuration.rate_limit_api_read_period_seconds = 30
    redis = MemoryRedis.new
    moment = Time.at(1_700_000_040)

    first = RecordingStudioApi::RateLimit.check(kind: :read, identifier: "credential:cred-1", redis: redis, now: moment)
    second = RecordingStudioApi::RateLimit.check(kind: :read, identifier: "credential:cred-1", redis: redis, now: moment)
    third = RecordingStudioApi::RateLimit.check(kind: :read, identifier: "credential:cred-1", redis: redis, now: moment)

    window = moment.to_i / 30
    expected_key = "recording_studio_api:api_read:credential:cred-1:#{window}"

    assert_equal true, first.allowed?
    assert_equal false, first.limited?
    assert_equal 1, first.count
    assert_equal 2, first.limit
    assert_equal 1, first.remaining
    assert_equal 30, first.retry_after
    assert_equal moment + 30, first.reset_at
    assert_equal expected_key, first.key

    assert_equal true, second.allowed?
    assert_equal 2, second.count
    assert_equal 0, second.remaining

    assert_equal false, third.allowed?
    assert_equal true, third.limited?
    assert_equal 3, third.count
    assert_equal 0, third.remaining
    assert_equal 30, third.retry_after

    assert_equal([expected_key, expected_key, expected_key], redis.eval_calls.map { |call| call.fetch(:keys).fetch(0) })
    assert_equal([30, 30, 30], redis.eval_calls.map { |call| call.fetch(:argv).fetch(0) })
    assert_equal RecordingStudioApi::RateLimit::INCR_EXPIRE_SCRIPT, redis.eval_calls.first.fetch(:script)
    assert_equal [[expected_key, 30]], redis.expire_calls
  end

  test "check uses the write limit and falls back when the specific limit is not positive" do
    RecordingStudioApi.configuration.rate_limit_api_write_requests = 0
    RecordingStudioApi.configuration.rate_limit_api_requests = 1
    RecordingStudioApi.configuration.rate_limit_api_write_period_seconds = 0
    RecordingStudioApi.configuration.rate_limit_api_period_seconds = 45
    redis = MemoryRedis.new

    policy = RecordingStudioApi::ApiRuntimePolicy.for(:public)
    assert_equal [1, 45], RecordingStudioApi::RateLimit.limits(kind: :write, policy: policy)

    first = RecordingStudioApi::RateLimit.check(kind: :write, identifier: "client:client-7", redis: redis)
    second = RecordingStudioApi::RateLimit.check(kind: :write, identifier: "client:client-7", redis: redis)

    assert_equal true, first.allowed?
    assert_equal 1, first.limit
    assert_equal 45, first.retry_after
    assert_includes first.key, ":api_write:client:client-7:"
    assert_equal false, second.allowed?
    assert_equal 2, second.count
  end

  test "a new window starts the counter again" do
    RecordingStudioApi.configuration.rate_limit_api_read_requests = 1
    RecordingStudioApi.configuration.rate_limit_api_read_period_seconds = 30
    redis = MemoryRedis.new
    start = Time.at(1_700_000_040)
    window = start.to_i / 30

    blocked = RecordingStudioApi::RateLimit.check(kind: :read, identifier: "actor:User:9", redis: redis, now: start)
    blocked_again = RecordingStudioApi::RateLimit.check(kind: :read, identifier: "actor:User:9", redis: redis, now: start + 10)
    rolled = RecordingStudioApi::RateLimit.check(kind: :read, identifier: "actor:User:9", redis: redis, now: start + 30)

    assert_equal true, blocked.allowed?
    assert_equal false, blocked_again.allowed?
    assert_equal "recording_studio_api:api_read:actor:User:9:#{window}", blocked.key
    assert_equal blocked.key, blocked_again.key
    assert_equal 2, blocked_again.count

    assert_equal true, rolled.allowed?
    assert_equal 1, rolled.count
    assert_equal "recording_studio_api:api_read:actor:User:9:#{window + 1}", rolled.key
  end

  test "clients without eval use incr and expire only on the first hit" do
    redis = IncrOnlyRedis.new
    moment = Time.at(1_700_000_100)

    first = RecordingStudioApi::RateLimit.check(
      kind: :read,
      identifier: "ip:10.0.0.8",
      limit: 5,
      period: 20,
      redis: redis,
      now: moment
    )
    second = RecordingStudioApi::RateLimit.check(
      kind: :read,
      identifier: "ip:10.0.0.8",
      limit: 5,
      period: 20,
      redis: redis,
      now: moment
    )

    assert_equal true, first.allowed?
    assert_equal 1, first.count
    assert_equal 20, first.retry_after
    assert_equal 2, second.count
    assert_equal [[first.key, 20]], redis.expire_calls
    assert_empty redis.eval_calls
  end

  test "explicit limit and period override the configured window" do
    RecordingStudioApi.configuration.rate_limit_api_read_requests = 100
    redis = MemoryRedis.new

    decision = RecordingStudioApi::RateLimit.check(
      kind: "api_read",
      identifier: "credential:cred-1",
      limit: 1,
      period: 15,
      namespace: "custom_ns",
      redis: redis,
      now: Time.at(1_500_000_000)
    )

    assert_equal 1, decision.limit
    assert_equal "custom_ns:api_read:credential:cred-1:#{1_500_000_000 / 15}", decision.key
    assert_equal true, decision.allowed?

    blocked = RecordingStudioApi::RateLimit.check(
      kind: "api_read",
      identifier: "credential:cred-1",
      limit: 1,
      period: 15,
      namespace: "custom_ns",
      redis: redis,
      now: Time.at(1_500_000_000)
    )
    assert_equal false, blocked.allowed?
  end

  test "check returns nil without incrementing when the limit is not positive or redis is missing" do
    redis = MemoryRedis.new

    assert_nil RecordingStudioApi::RateLimit.check(kind: :read, identifier: "credential:1", limit: 0, period: 30, redis: redis)
    assert_nil RecordingStudioApi::RateLimit.check(kind: :read, identifier: "credential:1", limit: 2, period: 0, redis: redis)
    assert_nil RecordingStudioApi::RateLimit.check(kind: :read, identifier: "credential:1", limit: 2, period: 30, redis: nil)
    assert_empty redis.eval_calls
  end

  test "check uses the shared redis client when one is not passed" do
    redis = MemoryRedis.new
    decision = RecordingStudioApi::Concerns::RateLimiting.stub(:redis_client, redis) do
      RecordingStudioApi::RateLimit.check(kind: :read, identifier: "credential:1", limit: 3, period: 10)
    end

    assert_equal 1, decision.count
    assert_equal 1, redis.eval_calls.length
  end

  test "deprecated script alias still points at the public script" do
    assert_equal(
      RecordingStudioApi::RateLimit::INCR_EXPIRE_SCRIPT,
      RecordingStudioApi::Concerns::RateLimiting::RATE_LIMIT_INCR_EXPIRE_SCRIPT
    )
  end

  test "a specific limit that is not positive falls back to the shared api limit" do
    RecordingStudioApi.configuration.rate_limit_api_read_requests = -3
    RecordingStudioApi.configuration.rate_limit_api_requests = 9
    RecordingStudioApi.configuration.rate_limit_api_read_period_seconds = 0
    RecordingStudioApi.configuration.rate_limit_api_period_seconds = 15

    policy = RecordingStudioApi::ApiRuntimePolicy.for(:public)

    assert_equal [9, 15], RecordingStudioApi::RateLimit.limits(kind: :read, policy: policy)
  end

  test "check returns nil when redis is missing and fail closed is off" do
    assert_equal false, RecordingStudioApi.configuration.rate_limit_check_fail_closed

    decision = RecordingStudioApi::RateLimit.check(
      kind: :read,
      identifier: "credential:1",
      limit: 2,
      period: 30,
      redis: nil
    )
    assert_nil decision

    error = assert_raises(RuntimeError) do
      RecordingStudioApi::RateLimit.check(
        kind: :read,
        identifier: "credential:1",
        limit: 2,
        period: 30,
        redis: BrokenRedis.new,
        fail_closed: false
      )
    end
    assert_equal "offline", error.message
  end

  test "check returns a limited decision when fail closed and redis is missing or raises" do
    moment = Time.at(1_700_000_040)
    missing = RecordingStudioApi::RateLimit.check(
      kind: :write,
      identifier: "client:client-7",
      limit: 4,
      period: 20,
      redis: nil,
      now: moment,
      fail_closed: true
    )
    raised = RecordingStudioApi::RateLimit.check(
      kind: :write,
      identifier: "client:client-7",
      limit: 4,
      period: 20,
      redis: BrokenRedis.new,
      now: moment,
      fail_closed: true
    )

    [missing, raised].each do |decision|
      assert_equal false, decision.allowed?
      assert_equal true, decision.limited?
      assert_equal 0, decision.count
      assert_equal 4, decision.limit
      assert_equal 0, decision.remaining
      assert_equal 20, decision.retry_after
      assert_equal moment + 20, decision.reset_at
      assert_equal "recording_studio_api:api_write:client:client-7:#{moment.to_i / 20}", decision.key
    end
  end

  test "fail closed defaults from config and an explicit false still returns nil" do
    RecordingStudioApi.configuration.rate_limit_check_fail_closed = true
    moment = Time.at(1_700_000_040)

    from_config = RecordingStudioApi::RateLimit.check(
      kind: :read,
      identifier: "credential:1",
      limit: 3,
      period: 10,
      redis: nil,
      now: moment
    )
    overridden = RecordingStudioApi::RateLimit.check(
      kind: :read,
      identifier: "credential:1",
      limit: 3,
      period: 10,
      redis: nil,
      now: moment,
      fail_closed: false
    )

    assert_equal false, from_config.allowed?
    assert_equal 0, from_config.count
    assert_nil overridden
  end

  test "fail closed still returns nil when the limit is not positive" do
    assert_nil RecordingStudioApi::RateLimit.check(
      kind: :read,
      identifier: "credential:1",
      limit: 0,
      period: 30,
      redis: nil,
      fail_closed: true
    )
  end

  test "check rejects an unknown kind a blank identifier and a half specified window" do
    assert_raises(ArgumentError) do
      RecordingStudioApi::RateLimit.key(kind: :read, identifier: "", window: 1)
    end
    assert_raises(ArgumentError) do
      RecordingStudioApi::RateLimit.check(kind: :other, identifier: "credential:1", limit: 1, period: 1, redis: MemoryRedis.new)
    end
    assert_raises(ArgumentError) do
      RecordingStudioApi::RateLimit.check(kind: :read, identifier: "credential:1", limit: 1, redis: MemoryRedis.new)
    end
  end
end
