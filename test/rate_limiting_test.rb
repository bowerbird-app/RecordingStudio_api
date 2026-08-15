# frozen_string_literal: true

require "test_helper"
require "redis"
require_relative "../app/controllers/recording_studio_api/concerns/rate_limiting"

class RateLimitingTest < ActiveSupport::TestCase
  class FakeResponse
    attr_reader :headers

    def initialize
      @headers = {}
    end

    def set_header(key, value)
      headers[key] = value
    end
  end

  class FakeRequest
    attr_reader :path, :remote_ip, :headers

    def initialize(path:, method:, remote_ip: "127.0.0.1", headers: {})
      @path = path
      @method = method.to_s.upcase
      @remote_ip = remote_ip
      @headers = headers
    end

    def get?
      @method == "GET"
    end
  end

  class FakeRedis
    attr_reader :incr_calls, :expire_calls, :ttl_calls, :eval_calls

    def initialize(incr_values:, ttl:)
      @incr_values = incr_values.dup
      @ttl = ttl
      @incr_calls = []
      @expire_calls = []
      @ttl_calls = []
      @eval_calls = []
      @counts = Hash.new(0)
      @effective_ttl = {}
    end

    def incr(key)
      incr_calls << key
      next_value = @incr_values.shift
      @counts[key] = next_value.nil? ? (@counts[key] + 1) : next_value
      @counts[key]
    end

    def expire(key, period)
      expire_calls << [key, period]
      @effective_ttl[key] = @ttl >= 0 ? @ttl : period
    end

    def ttl(key)
      ttl_calls << key
      return @effective_ttl.fetch(key) if @effective_ttl.key?(key)

      @ttl
    end

    def eval(_script, keys:, argv:)
      eval_calls << { keys: keys, argv: argv }
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

  class FakeLogger
    attr_reader :messages

    def initialize
      @messages = []
    end

    def warn(message)
      messages << message
    end
  end

  class Harness
    def self.before_action(*) = nil
    def self.prepend_before_action(*) = nil

    include RecordingStudioApi::Concerns::RateLimiting

    attr_reader :params, :request, :response, :rendered_payload, :current_api_credential, :current_api_client

    def initialize(path:, method:, params: {}, remote_ip: "127.0.0.1", current_api_credential: nil, current_api_client: nil, headers: {})
      @params = ActiveSupport::HashWithIndifferentAccess.new(params)
      @request = FakeRequest.new(path: path, method: method, remote_ip: remote_ip, headers: headers)
      @response = FakeResponse.new
      @current_api_credential = current_api_credential
      @current_api_client = current_api_client
      @rendered_payload = nil
    end

    def render(json:, status:)
      @rendered_payload = { json: json, status: status }
    end
  end

  def setup
    @original_configuration = RecordingStudioApi.instance_variable_get(:@configuration)
    RecordingStudioApi.instance_variable_set(:@configuration, RecordingStudioApi::Configuration.new)
    RecordingStudioApi::Concerns::RateLimiting.decider = nil
    RecordingStudioApi::Concerns::RateLimiting.reset_redis_client!
  end

  def teardown
    RecordingStudioApi::Concerns::RateLimiting.decider = nil
    RecordingStudioApi::Concerns::RateLimiting.reset_redis_client!
    RecordingStudioApi.instance_variable_set(:@configuration, @original_configuration)
  end

  test "computed api read decision uses configured namespace credential identifier and redis ttl" do
    RecordingStudioApi.configuration.rate_limit_api_enabled = true
    RecordingStudioApi.configuration.rate_limit_redis_namespace = "custom_ns"
    RecordingStudioApi.configuration.rate_limit_api_read_requests = 2
    RecordingStudioApi.configuration.rate_limit_api_read_period_seconds = 30

    credential = Struct.new(:id).new("cred-1")
    harness = Harness.new(
      path: "/recording_studio_api/api/v1/pages",
      method: :get,
      current_api_credential: credential
    )
    redis = FakeRedis.new(incr_values: [1], ttl: 28)

    decision = harness.stub(:rate_limit_redis_client, redis) do
      harness.send(:resolved_rate_limit_decision)
    end

    assert_equal false, decision.fetch(:limited)
    assert_equal 2, decision.fetch(:limit)
    assert_equal 1, decision.fetch(:remaining)
    assert_equal 28, decision.fetch(:retry_after)

    current_window = (Time.current.to_i / 30).to_i
    expected_key = "custom_ns:api_read:credential:cred-1:#{current_window}"
    assert_equal [expected_key], redis.incr_calls
    assert_equal [[expected_key, 30]], redis.expire_calls
    assert_equal 2, redis.ttl_calls.length
    assert_equal 1, redis.eval_calls.length
  end

  test "computed oauth decision applies an IP bucket before the recognized client bucket" do
    RecordingStudioApi.configuration.rate_limit_oauth_enabled = true
    RecordingStudioApi.configuration.rate_limit_oauth_requests = 2
    RecordingStudioApi.configuration.rate_limit_oauth_period_seconds = 60

    harness = Harness.new(
      path: "/recording_studio_api/oauth/token",
      method: :post,
      params: { client_id: "untrusted-client" },
      remote_ip: "203.0.113.9"
    )
    redis = FakeRedis.new(incr_values: [3], ttl: -1)

    decision = harness.stub(:rate_limit_redis_client, redis) do
      harness.send(:resolved_rate_limit_decision)
    end

    assert_equal true, decision.fetch(:limited)
    assert_equal 2, decision.fetch(:limit)
    assert_equal 0, decision.fetch(:remaining)
    assert_equal 60, decision.fetch(:retry_after)

    current_window = (Time.current.to_i / 60).to_i
    expected_key = "recording_studio_api:oauth:ip:203.0.113.9:#{current_window}"
    assert_equal [expected_key], redis.incr_calls
    assert_equal [[expected_key, 60]], redis.expire_calls
  end

  test "computed api pre auth decision uses ip identifier before bearer authentication" do
    RecordingStudioApi.configuration.rate_limit_api_pre_auth_enabled = true
    RecordingStudioApi.configuration.rate_limit_api_pre_auth_requests = 2
    RecordingStudioApi.configuration.rate_limit_api_pre_auth_period_seconds = 20

    harness = Harness.new(
      path: "/recording_studio_api/api/v1/pages",
      method: :get,
      remote_ip: "203.0.113.9"
    )
    redis = FakeRedis.new(incr_values: [3], ttl: 18)

    decision = harness.stub(:rate_limit_redis_client, redis) do
      harness.send(:with_rate_limit_bucket, "api_pre_auth") do
        harness.send(:resolved_rate_limit_decision)
      end
    end

    assert_equal true, decision.fetch(:limited)
    assert_equal 2, decision.fetch(:limit)
    assert_equal 0, decision.fetch(:remaining)
    assert_equal 18, decision.fetch(:retry_after)

    current_window = (Time.current.to_i / 20).to_i
    expected_key = "recording_studio_api:api_pre_auth:ip:203.0.113.9:#{current_window}"
    assert_equal [expected_key], redis.incr_calls
    # Counter already past the first hit with a live TTL, so EXPIRE is not rewritten.
    assert_equal [], redis.expire_calls
  end

  test "computed api write decision uses current api client identifier" do
    RecordingStudioApi.configuration.rate_limit_api_enabled = true
    RecordingStudioApi.configuration.rate_limit_api_write_requests = 3
    RecordingStudioApi.configuration.rate_limit_api_write_period_seconds = 45

    client = Struct.new(:id).new("client-7")
    harness = Harness.new(
      path: "/recording_studio_api/api/v1/workspaces",
      method: :post,
      current_api_client: client
    )
    redis = FakeRedis.new(incr_values: [1], ttl: 44)

    decision = harness.stub(:rate_limit_redis_client, redis) do
      harness.send(:resolved_rate_limit_decision)
    end

    assert_equal false, decision.fetch(:limited)
    assert_equal 3, decision.fetch(:limit)
    assert_equal 2, decision.fetch(:remaining)
    assert_equal 44, decision.fetch(:retry_after)

    expected_key_prefix = "recording_studio_api:api_write:client:client-7:"
    assert_equal true, redis.incr_calls.first.start_with?(expected_key_prefix)
  end

  test "rate limit identifier uses remote IP for OAuth requests regardless of the supplied client id" do
    oauth_harness = Harness.new(
      path: "/recording_studio_api/oauth/token",
      method: :post,
      params: { client_id: "attacker-controlled-client-id" },
      remote_ip: "10.0.0.9"
    )
    api_harness = Harness.new(path: "/recording_studio_api/api/v1/pages", method: :get, remote_ip: "10.0.0.10")

    assert_equal "ip:10.0.0.9", oauth_harness.send(:rate_limit_identifier)
    assert_equal "ip:10.0.0.10", api_harness.send(:rate_limit_identifier)
  end

  test "OAuth rate limiting cannot be bypassed by changing client IDs from the same IP" do
    RecordingStudioApi.configuration.rate_limit_oauth_enabled = true
    RecordingStudioApi.configuration.rate_limit_oauth_requests = 1
    RecordingStudioApi.configuration.rate_limit_oauth_period_seconds = 60

    harness = Harness.new(
      path: "/recording_studio_api/oauth/token",
      method: :post,
      params: { client_id: "first-untrusted-client" },
      remote_ip: "203.0.113.9"
    )
    redis = FakeRedis.new(incr_values: [1, 2], ttl: 59)

    harness.stub(:rate_limit_redis_client, redis) do
      harness.send(:enforce_rate_limit!)
      harness.params[:client_id] = "second-untrusted-client"
      harness.send(:enforce_rate_limit!)
    end

    assert_equal :too_many_requests, harness.rendered_payload.fetch(:status)
    assert_equal 2, redis.incr_calls.length
    assert_equal redis.incr_calls.first, redis.incr_calls.last
    assert_includes redis.incr_calls.first, ":oauth:ip:203.0.113.9:"
  end

  test "api pre auth limiter is disabled outside configured api version paths" do
    RecordingStudioApi.configuration.rate_limit_api_pre_auth_enabled = true

    harness = Harness.new(path: "/recording_studio_api/oauth/token", method: :post)

    assert_equal false, harness.send(:api_pre_auth_rate_limit_enabled_for_request?)
  end

  test "api pre auth limiter recognizes configured api versions" do
    RecordingStudioApi.configuration.rate_limit_api_pre_auth_enabled = true
    RecordingStudioApi.configuration.api_versions = ["v2"]
    RecordingStudioApi.configuration.default_api_version = "v2"

    harness = Harness.new(path: "/recording_studio_api/api/v2/pages", method: :get)

    assert_equal true, harness.send(:api_pre_auth_rate_limit_enabled_for_request?)
  end

  test "resolved decision logs and returns unlimited decision when decider raises" do
    logger = FakeLogger.new
    harness = Harness.new(path: "/recording_studio_api/api/v1/pages", method: :get)
    RecordingStudioApi::Concerns::RateLimiting.decider = lambda do |_controller|
      raise "redis offline"
    end

    decision = Rails.stub(:logger, logger) do
      harness.send(:resolved_rate_limit_decision)
    end

    assert_equal({ limited: false, limit: 0, remaining: 0, retry_after: 0 }, decision)
    assert_includes logger.messages.first, "rate limiter unavailable"
    assert_includes logger.messages.first, "redis offline"
  end

  test "resolved decision fails closed for configured oauth bucket when limiter is unavailable" do
    logger = FakeLogger.new
    RecordingStudioApi.configuration.rate_limit_oauth_enabled = true
    RecordingStudioApi.configuration.rate_limit_fail_closed = true
    RecordingStudioApi.configuration.rate_limit_fail_closed_buckets = %w[oauth api_pre_auth]
    RecordingStudioApi.configuration.rate_limit_oauth_requests = 10
    RecordingStudioApi.configuration.rate_limit_oauth_period_seconds = 60
    harness = Harness.new(path: "/recording_studio_api/oauth/token", method: :post, params: { client_id: "mobile-client" })
    RecordingStudioApi::Concerns::RateLimiting.decider = lambda do |_controller|
      raise "redis offline"
    end

    decision = Rails.stub(:logger, logger) do
      harness.send(:resolved_rate_limit_decision)
    end

    assert_equal({ limited: true, limit: 10, remaining: 0, retry_after: 60 }, decision)
    assert_includes logger.messages.first, "rate limiter unavailable"
  end

  test "resolved decision fails closed for enabled pre auth bucket when redis client is missing" do
    RecordingStudioApi.configuration.rate_limit_api_pre_auth_enabled = true
    RecordingStudioApi.configuration.rate_limit_fail_closed = true
    RecordingStudioApi.configuration.rate_limit_fail_closed_buckets = %w[oauth api_pre_auth]
    RecordingStudioApi.configuration.rate_limit_api_pre_auth_requests = 120
    RecordingStudioApi.configuration.rate_limit_api_pre_auth_period_seconds = 60
    harness = Harness.new(path: "/recording_studio_api/api/v1/pages", method: :get)

    decision = harness.stub(:rate_limit_redis_client, nil) do
      harness.send(:with_rate_limit_bucket, "api_pre_auth") do
        harness.send(:resolved_rate_limit_decision)
      end
    end

    assert_equal({ limited: true, limit: 120, remaining: 0, retry_after: 60 }, decision)
  end

  test "resolved decision still fails open for authenticated api bucket by default" do
    RecordingStudioApi.configuration.rate_limit_api_enabled = true
    RecordingStudioApi.configuration.rate_limit_fail_closed = true
    RecordingStudioApi.configuration.rate_limit_fail_closed_buckets = %w[oauth api_pre_auth]
    harness = Harness.new(path: "/recording_studio_api/api/v1/pages", method: :get)

    decision = harness.stub(:rate_limit_redis_client, nil) do
      harness.send(:resolved_rate_limit_decision)
    end

    assert_equal({ limited: false, limit: 0, remaining: 0, retry_after: 0 }, decision)
  end

  test "enforce_rate_limit renders too many requests response with headers" do
    harness = Harness.new(path: "/recording_studio_api/api/v1/pages", method: :get)

    harness.stub(:resolved_rate_limit_decision, { limited: true, limit: 4, remaining: 0, retry_after: 12 }) do
      harness.send(:enforce_rate_limit!)
    end

    assert_equal "12", harness.response.headers["Retry-After"]
    assert_equal "4", harness.response.headers["X-RateLimit-Limit"]
    assert_equal "0", harness.response.headers["X-RateLimit-Remaining"]
    assert_equal :too_many_requests, harness.rendered_payload.fetch(:status)
    assert_equal "rate_limit_exceeded", harness.rendered_payload.fetch(:json).fetch(:error)
  end

  test "rate limit redis client uses configured url timeouts and is reused" do
    harness = Harness.new(path: "/recording_studio_api/api/v1/pages", method: :get)
    fake_redis = Object.new
    RecordingStudioApi.configuration.rate_limit_redis_url = "redis://example.test:6379/4"
    RecordingStudioApi::Concerns::RateLimiting.reset_redis_client!
    constructed = 0

    Redis.stub(:new, lambda do |**kwargs|
      constructed += 1
      assert_equal "redis://example.test:6379/4", kwargs.fetch(:url)
      assert_equal 1, kwargs.fetch(:connect_timeout)
      assert_equal 1, kwargs.fetch(:read_timeout)
      assert_equal 1, kwargs.fetch(:write_timeout)
      fake_redis
    end) do
      first = harness.send(:rate_limit_redis_client)
      second = harness.send(:rate_limit_redis_client)
      assert_same fake_redis, first
      assert_same first, second
      assert_equal 1, constructed
    end
  end

  test "rate limit redis client returns nil on load error" do
    harness = Harness.new(path: "/recording_studio_api/api/v1/pages", method: :get)

    load_error_client = RecordingStudioApi::Concerns::RateLimiting.stub(:redis_client, nil) do
      harness.send(:rate_limit_redis_client)
    end

    assert_nil load_error_client
  end

  test "expires redis keys only on the first increment in a window" do
    RecordingStudioApi.configuration.rate_limit_api_enabled = true
    RecordingStudioApi.configuration.rate_limit_api_read_requests = 5
    RecordingStudioApi.configuration.rate_limit_api_read_period_seconds = 30

    harness = Harness.new(path: "/recording_studio_api/api/v1/pages", method: :get)
    redis = FakeRedis.new(incr_values: [1, 2, 3], ttl: -2)

    harness.stub(:rate_limit_redis_client, redis) do
      3.times { harness.send(:resolved_rate_limit_decision) }
    end

    assert_equal 3, redis.incr_calls.length
    assert_equal 1, redis.expire_calls.length
  end

  test "resets memoized redis client after a redis error" do
    RecordingStudioApi.configuration.rate_limit_api_enabled = true
    RecordingStudioApi.configuration.rate_limit_fail_closed = true
    RecordingStudioApi.configuration.rate_limit_fail_closed_buckets = %w[api_read]
    RecordingStudioApi.configuration.rate_limit_api_read_requests = 2
    RecordingStudioApi.configuration.rate_limit_api_read_period_seconds = 30

    harness = Harness.new(path: "/recording_studio_api/api/v1/pages", method: :get)
    broken = Object.new
    def broken.eval(*)
      raise "offline"
    end

    RecordingStudioApi::Concerns::RateLimiting.instance_variable_set(:@redis_client, broken)
    decision = harness.send(:resolved_rate_limit_decision)

    assert_equal true, decision.fetch(:limited)
    assert_nil RecordingStudioApi::Concerns::RateLimiting.instance_variable_get(:@redis_client)
  end

  test "skips pre-auth rate limit for bearer requests when authenticated api limits are enabled" do
    RecordingStudioApi.configuration.rate_limit_api_pre_auth_enabled = true
    RecordingStudioApi.configuration.rate_limit_api_enabled = true

    harness = Harness.new(
      path: "/recording_studio_api/api/v1/pages",
      method: :get,
      headers: { "Authorization" => "Bearer rsapi_at_token" }
    )

    assert harness.send(:skip_api_pre_auth_rate_limit_for_bearer?)

    called = false
    harness.stub(:enforce_rate_limit!, -> { called = true }) do
      harness.send(:enforce_api_pre_auth_rate_limit!)
    end
    refute called
  end

  test "keeps pre-auth rate limit for bearer requests when authenticated api limits are disabled" do
    RecordingStudioApi.configuration.rate_limit_api_pre_auth_enabled = true
    RecordingStudioApi.configuration.rate_limit_api_enabled = false

    harness = Harness.new(
      path: "/recording_studio_api/api/v1/pages",
      method: :get,
      headers: { "Authorization" => "Bearer rsapi_at_token" }
    )

    refute harness.send(:skip_api_pre_auth_rate_limit_for_bearer?)
  end
end
