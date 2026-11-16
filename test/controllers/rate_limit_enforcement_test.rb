# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"
require "redis"

class RateLimitEnforcementTest < ActionDispatch::IntegrationTest
  include ApiDummyHelpers

  class CountingRedis
    attr_reader :eval_keys

    def initialize
      @counts = Hash.new(0)
      @ttl = {}
      @eval_keys = []
    end

    def get(key)
      @counts[key]
    end

    def incr(key)
      @counts[key] += 1
    end

    def expire(key, period)
      @ttl[key] = period
    end

    def ttl(key)
      @ttl.fetch(key, -1)
    end

    def eval(_script, keys:, argv:)
      key = keys.fetch(0)
      eval_keys << key
      count = incr(key)
      current_ttl = ttl(key)
      if count == 1 || current_ttl.to_i.negative?
        expire(key, argv.fetch(0))
        current_ttl = ttl(key)
      end
      [count, current_ttl]
    end
  end

  class OfflineRedis
    def get(*)
      raise ::Redis::BaseError, "offline"
    end

    def eval(*)
      raise ::Redis::BaseError, "offline"
    end
  end

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user, role: :edit)
    @access_token = issue_oauth_access_token_for(access_recording: @access_recording, name: "Rate limit token")
    enable_http_limits!
  end

  teardown do
    RecordingStudioApi::Concerns::RateLimiting.decider = nil
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "bad bearer tokens hit the failed-auth limit" do
    RecordingStudioApi.configuration.rate_limit_api_failed_auth_requests = 2
    redis = CountingRedis.new

    statuses = with_redis(redis) { Array.new(3) { get pages_path, headers: bearer("not-a-real-token") } }

    assert_equal [401, 401, 429], statuses
    assert_equal "rate_limit_exceeded", JSON.parse(response.body).dig("error", "code")
    assert_equal(2, redis.eval_keys.count { |key| key.include?(":api_failed_auth:ip:") })
    assert_equal(2, redis.eval_keys.count { |key| key.include?(":api_pre_auth:ip:") })
    assert(redis.eval_keys.none? { |key| key.include?("not-a-real-token") })
  end

  test "a request with no token counts against the ip limit" do
    RecordingStudioApi.configuration.rate_limit_api_pre_auth_requests = 1
    redis = CountingRedis.new

    statuses = with_redis(redis) { Array.new(2) { get pages_path } }

    assert_equal [401, 429], statuses
    assert(redis.eval_keys.all? { |key| key.include?(":api_pre_auth:ip:") })
  end

  test "a valid token skips the ip limit" do
    RecordingStudioApi.configuration.rate_limit_api_pre_auth_requests = 1
    RecordingStudioApi.configuration.rate_limit_api_read_requests = 10
    redis = CountingRedis.new

    statuses = with_redis(redis) { Array.new(2) { get pages_path, headers: bearer(@access_token) } }

    assert_equal [200, 200], statuses
    assert(redis.eval_keys.none? { |key| key.include?(":api_pre_auth:") || key.include?(":api_failed_auth:") })
    assert(redis.eval_keys.all? { |key| key.include?(":api_read:credential:") })
  end

  test "a redis error still throttles authenticated reads from the in-process window" do
    RecordingStudioApi.configuration.rate_limit_api_read_requests = 1
    RecordingStudioApi.configuration.rate_limit_fail_closed_buckets = %w[oauth api_pre_auth api]

    statuses = with_redis(OfflineRedis.new) { Array.new(2) { get pages_path, headers: bearer(@access_token) } }

    assert_equal [200, 429], statuses
    assert_equal "rate_limit_exceeded", JSON.parse(response.body).dig("error", "code")
  end

  test "oauth and unauthenticated requests fail closed when redis raises" do
    RecordingStudioApi.configuration.rate_limit_oauth_enabled = true
    RecordingStudioApi.configuration.rate_limit_fail_closed_buckets = %w[oauth api_pre_auth api]
    redis = OfflineRedis.new

    with_redis(redis) do
      post "/recording_studio_api/oauth/token", params: { grant_type: "client_credentials" }
      assert_response :too_many_requests
      get pages_path
      assert_response :too_many_requests
    end
  end

  private

  def pages_path
    "/recording_studio_api/api/v1/pages"
  end

  def bearer(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def enable_http_limits!
    configuration = RecordingStudioApi.configuration
    configuration.rate_limit_api_enabled = true
    configuration.rate_limit_api_pre_auth_enabled = true
    configuration.rate_limit_api_failed_auth_enabled = true
    configuration.rate_limit_fail_closed = true
    configuration.rate_limit_api_pre_auth_requests = 50
    configuration.rate_limit_api_pre_auth_period_seconds = 60
    configuration.rate_limit_api_failed_auth_requests = 20
    configuration.rate_limit_api_failed_auth_period_seconds = 60
    configuration.rate_limit_api_read_requests = 30
    configuration.rate_limit_api_read_period_seconds = 60
  end

  def with_redis(redis)
    RecordingStudioApi::Concerns::RateLimiting.stub(:redis_client, redis) do
      statuses = yield
      statuses.is_a?(Array) ? statuses : nil
    end
  end

  def get(path, **kwargs)
    super
    response.status
  end
end
