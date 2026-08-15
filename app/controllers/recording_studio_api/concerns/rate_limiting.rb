# frozen_string_literal: true

module RecordingStudioApi
  module Concerns
    module RateLimiting
      extend ActiveSupport::Concern

      # Atomically increment and set TTL only on first hit in the window so we
      # avoid rewriting expiry on every request. Re-apply EXPIRE if TTL is missing.
      RATE_LIMIT_INCR_EXPIRE_SCRIPT = <<~LUA
        local count = redis.call("INCR", KEYS[1])
        local ttl = redis.call("TTL", KEYS[1])
        if count == 1 or ttl < 0 then
          redis.call("EXPIRE", KEYS[1], ARGV[1])
          ttl = redis.call("TTL", KEYS[1])
        end
        return { count, ttl }
      LUA

      class << self
        attr_accessor :decider

        def redis_client
          @redis_client_mutex ||= Mutex.new
          @redis_client_mutex.synchronize do
            return @redis_client if defined?(@redis_client) && !@redis_client.nil?

            require "redis"
            url = RecordingStudioApi.configuration.rate_limit_redis_url.to_s.strip
            options = {
              connect_timeout: 1,
              read_timeout: 1,
              write_timeout: 1
            }
            options[:url] = url if url.present?
            @redis_client = Redis.new(**options)
          end
        rescue LoadError
          nil
        end

        def reset_redis_client!
          @redis_client_mutex ||= Mutex.new
          @redis_client_mutex.synchronize do
            @redis_client = nil
          end
        end
      end

      included do
        prepend_before_action :enforce_api_pre_auth_rate_limit!
        before_action :enforce_rate_limit!
      end

      private

      def enforce_api_pre_auth_rate_limit!
        return unless api_pre_auth_rate_limit_enabled_for_request?
        return if skip_api_pre_auth_rate_limit_for_bearer?

        with_rate_limit_bucket("api_pre_auth") do
          enforce_rate_limit!
        end
      end

      # rubocop:disable Naming/PredicateMethod
      def enforce_rate_limit!
        current_rate_limit_exceeded?
      end
      # rubocop:enable Naming/PredicateMethod

      def current_rate_limit_exceeded?
        decision = resolved_rate_limit_decision
        return false unless decision[:limited]

        response.set_header("Retry-After", decision[:retry_after].to_i.to_s) if decision[:retry_after].to_i.positive?
        response.set_header("X-RateLimit-Limit", decision[:limit].to_i.to_s)
        response.set_header("X-RateLimit-Remaining", decision[:remaining].to_i.to_s)

        @rate_limited_request = true
        render json: rate_limit_exceeded_payload, status: :too_many_requests
        true
      end

      def rate_limit_exceeded_payload
        if oauth_rate_limited_path?
          { error: "rate_limit_exceeded", error_description: "Too many requests" }
        elsif respond_to?(:api_error_payload, true)
          api_error_payload(code: "rate_limit_exceeded", message: "Too many requests")
        else
          { error: { code: "rate_limit_exceeded", message: "Too many requests" } }
        end
      end

      def resolved_rate_limit_decision
        decider = RateLimiting.decider
        injected_decision = if decider.nil?
                              nil
                            elsif decider.arity == 0
                              decider.call
                            else
                              decider.call(self)
                            end
        return normalize_decision(injected_decision) if injected_decision.present?

        computed_decision = computed_rate_limit_decision
        return normalize_decision(computed_decision) if computed_decision.present?

        fail_closed_rate_limit_decision
      rescue StandardError => error
        Rails.logger.warn("[RecordingStudioApi] rate limiter unavailable: #{error.class}: #{error.message}")
        RateLimiting.reset_redis_client!
        fail_closed_rate_limit_decision
      end

      def computed_rate_limit_decision
        return nil unless rate_limit_enabled_for_request?

        redis = rate_limit_redis_client
        return nil if redis.nil?

        limit = rate_limit_window_limit
        period = rate_limit_window_period
        return nil if limit <= 0 || period <= 0

        current_window = (Time.current.to_i / period).to_i
        key = "#{rate_limit_scoped_namespace}:#{rate_limit_bucket}:#{rate_limit_identifier}:#{current_window}"

        count, retry_after = increment_rate_limit_counter(redis, key, period)
        remaining = [limit - count, 0].max

        {
          limited: count > limit,
          limit: limit,
          remaining: remaining,
          retry_after: retry_after.positive? ? retry_after : period
        }
      end

      def increment_rate_limit_counter(redis, key, period)
        if redis.respond_to?(:eval)
          result = redis.eval(RATE_LIMIT_INCR_EXPIRE_SCRIPT, keys: [key], argv: [period.to_i])
          return [result[0].to_i, result[1].to_i]
        end

        count = redis.incr(key)
        ttl = redis.ttl(key)
        if count == 1 || ttl.to_i < 0
          redis.expire(key, period)
          ttl = redis.ttl(key)
        end
        [count, ttl.to_i]
      end

      def normalize_decision(decision)
        payload = decision.is_a?(Hash) ? decision.symbolize_keys : {}

        {
          limited: payload.fetch(:limited, false),
          limit: payload.fetch(:limit, 0),
          remaining: payload.fetch(:remaining, 0),
          retry_after: payload.fetch(:retry_after, 0)
        }
      end

      def fail_closed_rate_limit_decision
        return normalize_decision(nil) unless rate_limit_fail_closed_for_request?

        {
          limited: true,
          limit: rate_limit_window_limit,
          remaining: 0,
          retry_after: rate_limit_window_period
        }
      end

      def rate_limit_fail_closed_for_request?
        return false unless RecordingStudioApi.configuration.rate_limit_fail_closed
        return false unless rate_limit_enabled_for_request?
        return false unless rate_limit_window_limit.to_i.positive? && rate_limit_window_period.to_i.positive?

        Array(RecordingStudioApi.configuration.rate_limit_fail_closed_buckets).map(&:to_s).include?(rate_limit_bucket)
      end

      def with_rate_limit_bucket(bucket)
        previous_bucket = @rate_limit_bucket_override
        @rate_limit_bucket_override = bucket
        yield
      ensure
        @rate_limit_bucket_override = previous_bucket
      end

      def api_pre_auth_rate_limit_enabled_for_request? = rate_limit_api.rate_limit_api_pre_auth_enabled && api_rate_limited_path?

      # Skip the IP pre-auth bucket when a Bearer token is present and authenticated API
      # rate limits are enabled. Invalid Bearer traffic still hits pre-auth when API RL is off.
      def skip_api_pre_auth_rate_limit_for_bearer?
        return false unless rate_limit_api.rate_limit_api_enabled

        bearer_authorization_header_present?
      end

      def bearer_authorization_header_present?
        authorization = request.headers["Authorization"].to_s
        authorization.match?(/\ABearer\s+\S+/i)
      end

      def rate_limit_enabled_for_request?
        if rate_limit_bucket_override == "api_pre_auth"
          return api_pre_auth_rate_limit_enabled_for_request?
        end
        if oauth_rate_limited_path?
          return rate_limit_api.rate_limit_oauth_enabled
        end

        return false unless rate_limit_api.rate_limit_api_enabled

        api_rate_limited_path?
      end

      def rate_limit_bucket
        return rate_limit_bucket_override if rate_limit_bucket_override.present?

        if oauth_rate_limited_path?
          "oauth"
        elsif api_read_request?
          "api_read"
        else
          "api_write"
        end
      end

      def rate_limit_window_limit
        case rate_limit_bucket
        when "oauth"
          rate_limit_api.rate_limit_oauth_requests.to_i
        when "api_pre_auth"
          rate_limit_api.rate_limit_api_pre_auth_requests.to_i
        when "api_read"
          rate_limit_api.rate_limit_api_read_requests.to_i.nonzero? ||
            rate_limit_api.rate_limit_api_requests.to_i
        else
          rate_limit_api.rate_limit_api_write_requests.to_i.nonzero? ||
            rate_limit_api.rate_limit_api_requests.to_i
        end
      end

      def rate_limit_window_period
        case rate_limit_bucket
        when "oauth"
          rate_limit_api.rate_limit_oauth_period_seconds.to_i
        when "api_pre_auth"
          rate_limit_api.rate_limit_api_pre_auth_period_seconds.to_i
        when "api_read"
          rate_limit_api.rate_limit_api_read_period_seconds.to_i.nonzero? ||
            rate_limit_api.rate_limit_api_period_seconds.to_i
        else
          rate_limit_api.rate_limit_api_write_period_seconds.to_i.nonzero? ||
            rate_limit_api.rate_limit_api_period_seconds.to_i
        end
      end

      def rate_limit_identifier
        return "ip:#{request.remote_ip}" if %w[oauth api_pre_auth].include?(rate_limit_bucket)

        if respond_to?(:current_api_credential, true) && current_api_credential.present?
          "credential:#{current_api_credential.id}"
        elsif respond_to?(:current_api_client, true) && current_api_client.present?
          "client:#{current_api_client.id}"
        else
          "ip:#{request.remote_ip}"
        end
      end

      def rate_limit_namespace
        configured = RecordingStudioApi.configuration.rate_limit_redis_namespace.to_s.strip
        configured.present? ? configured : "recording_studio_api"
      end

      def rate_limit_api
        return current_api if respond_to?(:current_api, true)

        RecordingStudioApi.configuration
      end

      def rate_limit_scoped_namespace
        api_key = respond_to?(:current_api_key, true) ? current_api_key.to_s : "public"
        return rate_limit_namespace if api_key.blank? || api_key == "public"

        "#{rate_limit_namespace}:#{api_key}"
      end

      def rate_limit_bucket_override = @rate_limit_bucket_override

      def oauth_rate_limited_path?
        request.path.end_with?("/oauth/token", "/oauth/revoke")
      end

      def api_rate_limited_path?
        public_api_path = RecordingStudioApi.api_versions.any? do |version|
          request.path.include?("/api/#{version}/") || request.path.end_with?("/api/#{version}")
        end
        named_api_path = request.path.match?(%r{/apis/[a-z0-9_-]+/v[a-z0-9_-]+(?:/|\z)}i)

        public_api_path || named_api_path
      end

      def api_read_request?
        api_rate_limited_path? && request.get?
      end

      def rate_limit_redis_client
        RateLimiting.redis_client
      end
    end
  end
end
