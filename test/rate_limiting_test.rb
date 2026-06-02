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
    attr_reader :path, :remote_ip

    def initialize(path:, method:, remote_ip: "127.0.0.1")
      @path = path
      @method = method.to_s.upcase
      @remote_ip = remote_ip
    end

    def get?
      @method == "GET"
    end
  end

  class FakeRedis
    attr_reader :incr_calls, :expire_calls, :ttl_calls

    def initialize(incr_values:, ttl:)
      @incr_values = incr_values.dup
      @ttl = ttl
      @incr_calls = []
      @expire_calls = []
      @ttl_calls = []
    end

    def incr(key)
      incr_calls << key
      @incr_values.shift || @incr_values.last || 1
    end

    def expire(key, period)
      expire_calls << [key, period]
    end

    def ttl(key)
      ttl_calls << key
      @ttl
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

    def initialize(path:, method:, params: {}, remote_ip: "127.0.0.1", current_api_credential: nil, current_api_client: nil)
      @params = ActiveSupport::HashWithIndifferentAccess.new(params)
      @request = FakeRequest.new(path: path, method: method, remote_ip: remote_ip)
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
  end

  def teardown
    RecordingStudioApi::Concerns::RateLimiting.decider = nil
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
    assert_equal [expected_key], redis.ttl_calls
  end

  test "computed oauth decision uses client id bucket and falls back to period when ttl is not positive" do
    RecordingStudioApi.configuration.rate_limit_oauth_enabled = true
    RecordingStudioApi.configuration.rate_limit_oauth_requests = 1
    RecordingStudioApi.configuration.rate_limit_oauth_period_seconds = 60

    harness = Harness.new(
      path: "/recording_studio_api/oauth/token",
      method: :post,
      params: { client_id: "mobile-client" }
    )
    redis = FakeRedis.new(incr_values: [2], ttl: -1)

    decision = harness.stub(:rate_limit_redis_client, redis) do
      harness.send(:resolved_rate_limit_decision)
    end

    assert_equal true, decision.fetch(:limited)
    assert_equal 1, decision.fetch(:limit)
    assert_equal 0, decision.fetch(:remaining)
    assert_equal 60, decision.fetch(:retry_after)

    current_window = (Time.current.to_i / 60).to_i
    expected_key = "recording_studio_api:oauth:client:mobile-client:#{current_window}"
    assert_equal [expected_key], redis.incr_calls
    assert_equal [], redis.expire_calls
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

  test "rate limit identifier falls back to remote ip when oauth client id or api credentials are unavailable" do
    oauth_harness = Harness.new(path: "/recording_studio_api/oauth/revoke", method: :post, remote_ip: "10.0.0.9")
    api_harness = Harness.new(path: "/recording_studio_api/api/v1/pages", method: :get, remote_ip: "10.0.0.10")

    assert_equal "ip:10.0.0.9", oauth_harness.send(:rate_limit_identifier)
    assert_equal "ip:10.0.0.10", api_harness.send(:rate_limit_identifier)
  end

  test "api pre auth limiter is disabled outside api v1 paths" do
    RecordingStudioApi.configuration.rate_limit_api_pre_auth_enabled = true

    harness = Harness.new(path: "/recording_studio_api/oauth/token", method: :post)

    assert_equal false, harness.send(:api_pre_auth_rate_limit_enabled_for_request?)
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

  test "rate limit redis client uses configured url and returns nil on load error" do
    harness = Harness.new(path: "/recording_studio_api/api/v1/pages", method: :get)
    fake_redis = Object.new
    RecordingStudioApi.configuration.rate_limit_redis_url = "redis://example.test:6379/4"

    redis_client = Redis.stub(:new, lambda do |**kwargs|
      assert_equal({ url: "redis://example.test:6379/4" }, kwargs)
      fake_redis
    end) do
      harness.send(:rate_limit_redis_client)
    end

    assert_same fake_redis, redis_client

    load_error_client = harness.stub(:require, ->(_dependency) { raise LoadError }) do
      harness.send(:rate_limit_redis_client)
    end

    assert_nil load_error_client
  end
end