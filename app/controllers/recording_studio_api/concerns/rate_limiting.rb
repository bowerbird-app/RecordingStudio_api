# frozen_string_literal: true

module RecordingStudioApi
  module Concerns
    module RateLimiting
      extend ActiveSupport::Concern

      # Deprecated. Use RecordingStudioApi::RateLimit::INCR_EXPIRE_SCRIPT.
      # Kept so this patch release does not drop a constant other gems already call.
      RATE_LIMIT_INCR_EXPIRE_SCRIPT = RecordingStudioApi::RateLimit::INCR_EXPIRE_SCRIPT
      IP_BUCKETS = %w[oauth api_pre_auth api_failed_auth].freeze
      MEMORY_FALLBACK_BUCKETS = %w[api_read api_write].freeze

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
        prepend_before_action :enforce_api_failed_auth_gate!
        before_action :enforce_rate_limit!
      end

      private

      def enforce_api_failed_auth_gate!
        return unless failed_auth_rate_limit_enabled_for_request?
        return unless bearer_authorization_header_present?

        with_rate_limit_bucket("api_failed_auth") do
          limit = rate_limit_window_limit.to_i
          next unless limit.positive?
          next if failed_auth_window_count < limit

          render_limited_decision(
            limited: true,
            limit: limit,
            remaining: 0,
            retry_after: rate_limit_window_period
          )
        end
      end

      def enforce_api_pre_auth_rate_limit!
        return unless api_pre_auth_rate_limit_enabled_for_request?
        return if bearer_authorization_header_present?

        with_rate_limit_bucket("api_pre_auth") do
          enforce_rate_limit!
        end
      end

      # Returns true after rendering 429 so the caller can skip the 401.
      # rubocop:disable-next Naming/PredicateMethod
      def count_failed_authentication!
        return false unless rejected_bearer_counts?

        limited_decision = nil
        if api_pre_auth_rate_limit_enabled_for_request?
          decision = with_rate_limit_bucket("api_pre_auth") { resolved_rate_limit_decision }
          limited_decision = decision if decision[:limited]
        end
        if failed_auth_rate_limit_enabled_for_request?
          decision = with_rate_limit_bucket("api_failed_auth") { resolved_rate_limit_decision }
          limited_decision = decision if decision[:limited]
        end
        return false unless limited_decision

        render_limited_decision(limited_decision)
        true
      end

      # rubocop:disable-next Naming/PredicateMethod
      def enforce_rate_limit!
        current_rate_limit_exceeded?
      end

      def current_rate_limit_exceeded?
        render_limited_decision(resolved_rate_limit_decision)
      end

      # rubocop:disable-next Naming/PredicateMethod
      def render_limited_decision(decision)
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
        return memory_fallback_decision(missing_store_error) if memory_fallback_for_missing_store?

        fail_closed_rate_limit_decision
      rescue StandardError => error
        Rails.logger.warn("[RecordingStudioApi] rate limiter unavailable: #{error.class}: #{error.message}")
        RateLimiting.reset_redis_client!
        return memory_fallback_decision(error) if memory_fallback_for_store_error?(error)

        fail_closed_rate_limit_decision
      end

      def computed_rate_limit_decision
        return nil unless rate_limit_enabled_for_request?

        limit, period = rate_limit_window
        decision = RecordingStudioApi::RateLimit.check(
          kind: rate_limit_bucket,
          identifier: rate_limit_identifier,
          limit: limit,
          period: period,
          namespace: rate_limit_scoped_namespace,
          redis: rate_limit_redis_client,
          fail_closed: false
        )
        return nil unless decision

        {
          limited: decision.limited?,
          limit: decision.limit,
          remaining: decision.remaining,
          retry_after: decision.retry_after
        }
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

        return true if rate_limit_bucket == "api_failed_auth"

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

      def failed_auth_rate_limit_enabled_for_request? = rate_limit_api.rate_limit_api_failed_auth_enabled && api_rate_limited_path?

      def rejected_bearer_counts?
        bearer_authorization_header_present? && api_rate_limited_path?
      end

      def bearer_authorization_header_present?
        authorization = request.headers["Authorization"].to_s
        authorization.match?(/\ABearer\s+\S+/i)
      end

      def rate_limit_enabled_for_request?
        if rate_limit_bucket_override == "api_pre_auth"
          return api_pre_auth_rate_limit_enabled_for_request?
        end
        if rate_limit_bucket_override == "api_failed_auth"
          return failed_auth_rate_limit_enabled_for_request?
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

      def rate_limit_window
        RecordingStudioApi::RateLimit.limits(kind: rate_limit_bucket, policy: rate_limit_api)
      end

      def rate_limit_window_limit
        rate_limit_window.first
      end

      def rate_limit_window_period
        rate_limit_window.last
      end

      def rate_limit_identifier
        return "ip:#{request.remote_ip}" if IP_BUCKETS.include?(rate_limit_bucket)

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
        return current_runtime_policy if respond_to?(:current_runtime_policy, true)

        RecordingStudioApi::ApiRuntimePolicy.for(:public)
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

      def memory_fallback_for_missing_store?
        return false unless memory_fallback_bucket?
        return false unless rate_limit_enabled_for_request?

        limit, period = rate_limit_window
        return false unless limit.to_i.positive? && period.to_i.positive?

        rate_limit_redis_client.nil?
      end

      def memory_fallback_for_store_error?(error)
        memory_fallback_bucket? && RecordingStudioApi::RateLimit.store_error?(error)
      end

      def memory_fallback_bucket?
        MEMORY_FALLBACK_BUCKETS.include?(rate_limit_bucket)
      end

      def missing_store_error
        RecordingStudioApi::RateLimit::StoreUnavailable.new("Redis client is missing")
      end

      def memory_fallback_decision(error)
        limit, period = rate_limit_window
        count, retry_after = RecordingStudioApi::RateLimit::ProcessWindow.increment(rate_limit_counter_key, period)
        report_rate_limit_fallback(error)
        {
          limited: count > limit.to_i,
          limit: limit.to_i,
          remaining: [limit.to_i - count, 0].max,
          retry_after: retry_after
        }
      end

      def rate_limit_counter_key
        period = rate_limit_window_period.to_i
        RecordingStudioApi::RateLimit.key(
          kind: rate_limit_bucket,
          identifier: rate_limit_identifier,
          window: Time.current.to_i / period,
          namespace: rate_limit_scoped_namespace
        )
      end

      def failed_auth_window_count
        return 0 unless rate_limit_window_period.to_i.positive?

        client = rate_limit_redis_client
        raise RecordingStudioApi::RateLimit::StoreUnavailable, "Redis client is missing" if client.nil?

        client.get(rate_limit_counter_key).to_i
      rescue StandardError => error
        raise unless RecordingStudioApi::RateLimit.store_error?(error)

        # A failed read cannot tell a good token from a bad one. Let authentication
        # run. A rejected bearer still fails closed below. A valid credential
        # reaches the read or write limit, which uses the in-process window.
        Rails.logger.warn("[RecordingStudioApi] rate limiter unavailable: #{error.class}: #{error.message}")
        RateLimiting.reset_redis_client!
        0
      end

      def report_rate_limit_fallback(error)
        Rails.logger.warn(
          "[RecordingStudioApi] rate limit #{rate_limit_bucket} fell back to the in-process window (#{error.class}: #{error.message})"
        )
        return unless defined?(Rails) && Rails.respond_to?(:error) && Rails.error.respond_to?(:report)

        Rails.error.report(
          error,
          handled: true,
          severity: :warning,
          context: { bucket: rate_limit_bucket, fallback: "process_window" }
        )
      rescue StandardError
        nil
      end
    end
  end
end
