# frozen_string_literal: true

module RecordingStudioApi
  # Fixed-window counter shared by HTTP rate limiting and other gems.
  #
  # Key layout, unchanged from the HTTP limiter:
  #   {namespace}:{kind}:{identifier}:{window}
  #
  # `kind` is `api_read`, `api_write`, `oauth`, or `api_pre_auth`.
  # `window` is `now.to_i / period`. The default namespace is
  # `recording_studio_api`.
  class RateLimit
    # First hit in the window sets the TTL. Later hits leave it alone.
    # A key that lost its TTL gets EXPIRE again.
    INCR_EXPIRE_SCRIPT = <<~LUA
      local count = redis.call("INCR", KEYS[1])
      local ttl = redis.call("TTL", KEYS[1])
      if count == 1 or ttl < 0 then
        redis.call("EXPIRE", KEYS[1], ARGV[1])
        ttl = redis.call("TTL", KEYS[1])
      end
      return { count, ttl }
    LUA

    Decision = Data.define(
      :allowed,
      :count,
      :limit,
      :remaining,
      :retry_after,
      :reset_at,
      :key
    ) do
      def allowed? = allowed

      def limited? = !allowed
    end

    BUCKETS = {
      "read" => "api_read",
      "api_read" => "api_read",
      "write" => "api_write",
      "api_write" => "api_write",
      "oauth" => "oauth",
      "api_pre_auth" => "api_pre_auth"
    }.freeze

    class << self
      def key(kind:, identifier:, window:, namespace: nil, api: nil)
        raise ArgumentError, "identifier is required" if identifier.blank?
        raise ArgumentError, "window is required" if window.nil?

        "#{prefix_for(namespace, api)}:#{bucket_for(kind)}:#{identifier}:#{window}"
      end

      # [limit, period_seconds] for a runtime policy. Read and write fall
      # back to the shared API limit when the specific value is not positive.
      def limits(kind:, policy:)
        case bucket_for(kind)
        when "oauth"
          [policy.rate_limit_oauth_requests.to_i, policy.rate_limit_oauth_period_seconds.to_i]
        when "api_pre_auth"
          [policy.rate_limit_api_pre_auth_requests.to_i, policy.rate_limit_api_pre_auth_period_seconds.to_i]
        when "api_read"
          [
            positive_or(policy.rate_limit_api_read_requests, policy.rate_limit_api_requests),
            positive_or(policy.rate_limit_api_read_period_seconds, policy.rate_limit_api_period_seconds)
          ]
        else
          [
            positive_or(policy.rate_limit_api_write_requests, policy.rate_limit_api_requests),
            positive_or(policy.rate_limit_api_write_period_seconds, policy.rate_limit_api_period_seconds)
          ]
        end
      end

      # Increments the counter for this window and compares it to the limit.
      #
      # Returns nil when the limit or period is not positive. Nothing was counted.
      # Returns nil when Redis is missing and fail closed is off. A Redis or
      # connection error is logged, and the shared client is reset. Fail closed
      # then returns a limited decision. Otherwise that error propagates.
      # Any other error propagates immediately. `fail_closed:` must be nil,
      # true, or false. nil reads `config.rate_limit_check_fail_closed`, which
      # defaults to false.
      #
      # Omit `limit` and `period` to use {.limits} for `api` (default `:public`).
      # Omit `redis` to use the shared rate-limit client.
      def check(kind:, identifier:, api: :public, namespace: nil, limit: nil, period: nil, redis: :shared, now: nil, fail_closed: nil)
        resolved_limit, resolved_period = resolve_limits(kind, limit, period, api)
        return nil if resolved_limit <= 0 || resolved_period <= 0

        close_on_failure = resolve_fail_closed(fail_closed)
        moment = now || Time.current
        counter_key = key(kind: kind, identifier: identifier, window: moment.to_i / resolved_period, namespace: namespace, api: api)
        shared_client = redis.equal?(:shared)
        count, ttl = begin
          client = shared_client ? shared_redis : redis
          if client.nil?
            return closed_decision(resolved_limit, resolved_period, moment, counter_key) if close_on_failure

            return nil
          end

          increment(client, counter_key, resolved_period)
        rescue StandardError => e
          raise unless redis_unavailable?(e)

          warn_redis_unavailable(e)
          reset_shared_redis! if shared_client
          raise unless close_on_failure

          return closed_decision(resolved_limit, resolved_period, moment, counter_key)
        end

        retry_after = ttl.positive? ? ttl : resolved_period
        Decision.new(
          allowed: count <= resolved_limit,
          count: count,
          limit: resolved_limit,
          remaining: [resolved_limit - count, 0].max,
          retry_after: retry_after,
          reset_at: moment + retry_after,
          key: counter_key
        )
      end

      private

      def resolve_limits(kind, limit, period, api)
        return [limit.to_i, period.to_i] if !limit.nil? && !period.nil?
        raise ArgumentError, "Pass limit and period together" if !limit.nil? || !period.nil?

        limits(kind: kind, policy: RecordingStudioApi::ApiRuntimePolicy.for(api))
      end

      def increment(redis, key, period)
        if redis.respond_to?(:eval)
          result = redis.eval(INCR_EXPIRE_SCRIPT, keys: [key], argv: [period.to_i])
          return [result[0].to_i, result[1].to_i]
        end

        count = redis.incr(key)
        ttl = redis.ttl(key)
        if count == 1 || ttl.to_i.negative?
          redis.expire(key, period)
          ttl = redis.ttl(key)
        end
        [count.to_i, ttl.to_i]
      end

      def shared_redis
        RecordingStudioApi::Concerns::RateLimiting.redis_client
      end

      def prefix_for(namespace, api)
        explicit = namespace.to_s.strip
        return explicit if explicit.present?

        configured = RecordingStudioApi.configuration.rate_limit_redis_namespace.to_s.strip
        base = configured.present? ? configured : "recording_studio_api"
        name = api.to_s.strip
        return base if name.empty? || name == "public"

        "#{base}:#{name}"
      end

      def bucket_for(kind)
        BUCKETS.fetch(kind.to_s) { raise ArgumentError, "Unknown rate limit kind: #{kind.inspect}" }
      end

      # Not positive falls back. `positive?` matches that: 0 and negatives use the shared limit.
      def positive_or(specific, fallback)
        value = specific.to_i
        value.positive? ? value : fallback.to_i
      end

      def resolve_fail_closed(value)
        resolved = value.nil? ? RecordingStudioApi.configuration.rate_limit_check_fail_closed : value
        return resolved if [true, false].include?(resolved)

        raise ArgumentError, "fail_closed must be true or false"
      end

      def redis_unavailable?(error)
        return true if error.is_a?(Errno::ECONNREFUSED) || error.is_a?(IOError) || error.is_a?(Timeout::Error)
        return true if defined?(Redis::BaseError) && error.is_a?(Redis::BaseError)
        return true if defined?(RedisClient::Error) && error.is_a?(RedisClient::Error)

        false
      end

      def warn_redis_unavailable(error)
        return unless defined?(Rails) && Rails.respond_to?(:logger)

        Rails.logger&.warn("[RecordingStudioApi] rate limiter unavailable: #{error.class}: #{error.message}")
      end

      def reset_shared_redis!
        RecordingStudioApi::Concerns::RateLimiting.reset_redis_client!
      end

      def closed_decision(limit, period, moment, counter_key)
        Decision.new(
          allowed: false,
          count: 0,
          limit: limit,
          remaining: 0,
          retry_after: period,
          reset_at: moment + period,
          key: counter_key
        )
      end
    end
  end
end
