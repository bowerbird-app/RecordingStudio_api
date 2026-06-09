# frozen_string_literal: true

module RecordingStudioApi
  module Concerns
    module RateLimiting
      extend ActiveSupport::Concern

      class << self
        attr_accessor :decider
      end

      included do
        prepend_before_action :enforce_api_pre_auth_rate_limit!
        before_action :enforce_rate_limit!
      end

      private

      def enforce_api_pre_auth_rate_limit!
        return unless api_pre_auth_rate_limit_enabled_for_request?

        with_rate_limit_bucket("api_pre_auth") do
          enforce_rate_limit!
        end
      end

      def enforce_rate_limit!
        decision = resolved_rate_limit_decision
        return unless decision[:limited]

        response.set_header("Retry-After", decision[:retry_after].to_i.to_s) if decision[:retry_after].to_i.positive?
        response.set_header("X-RateLimit-Limit", decision[:limit].to_i.to_s)
        response.set_header("X-RateLimit-Remaining", decision[:remaining].to_i.to_s)

        @rate_limited_request = true
        render json: { error: "rate_limit_exceeded", error_description: "Too many requests" }, status: :too_many_requests
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

        normalize_decision(computed_rate_limit_decision)
      rescue StandardError => error
        Rails.logger.warn("[RecordingStudioApi] rate limiter unavailable: #{error.class}: #{error.message}")
        normalize_decision(nil)
      end

      def computed_rate_limit_decision
        return nil unless rate_limit_enabled_for_request?

        redis = rate_limit_redis_client
        return nil if redis.nil?

        limit = rate_limit_window_limit
        period = rate_limit_window_period
        return nil if limit <= 0 || period <= 0

        current_window = (Time.current.to_i / period).to_i
        key = "#{rate_limit_namespace}:#{rate_limit_bucket}:#{rate_limit_identifier}:#{current_window}"

        count = redis.incr(key)
        redis.expire(key, period) if count == 1

        remaining = [limit - count, 0].max
        retry_after = redis.ttl(key)

        {
          limited: count > limit,
          limit: limit,
          remaining: remaining,
          retry_after: retry_after.positive? ? retry_after : period
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

      def with_rate_limit_bucket(bucket)
        previous_bucket = @rate_limit_bucket_override
        @rate_limit_bucket_override = bucket
        yield
      ensure
        @rate_limit_bucket_override = previous_bucket
      end

      def api_pre_auth_rate_limit_enabled_for_request? = RecordingStudioApi.configuration.rate_limit_api_pre_auth_enabled && api_rate_limited_path?

      def rate_limit_enabled_for_request?
        if rate_limit_bucket_override == "api_pre_auth"
          return api_pre_auth_rate_limit_enabled_for_request?
        end
        if oauth_rate_limited_path?
          return RecordingStudioApi.configuration.rate_limit_oauth_enabled
        end

        return false unless RecordingStudioApi.configuration.rate_limit_api_enabled

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
          RecordingStudioApi.configuration.rate_limit_oauth_requests.to_i
        when "api_pre_auth"
          RecordingStudioApi.configuration.rate_limit_api_pre_auth_requests.to_i
        when "api_read"
          RecordingStudioApi.configuration.rate_limit_api_read_requests.to_i.nonzero? ||
            RecordingStudioApi.configuration.rate_limit_api_requests.to_i
        else
          RecordingStudioApi.configuration.rate_limit_api_write_requests.to_i.nonzero? ||
            RecordingStudioApi.configuration.rate_limit_api_requests.to_i
        end
      end

      def rate_limit_window_period
        case rate_limit_bucket
        when "oauth"
          RecordingStudioApi.configuration.rate_limit_oauth_period_seconds.to_i
        when "api_pre_auth"
          RecordingStudioApi.configuration.rate_limit_api_pre_auth_period_seconds.to_i
        when "api_read"
          RecordingStudioApi.configuration.rate_limit_api_read_period_seconds.to_i.nonzero? ||
            RecordingStudioApi.configuration.rate_limit_api_period_seconds.to_i
        else
          RecordingStudioApi.configuration.rate_limit_api_write_period_seconds.to_i.nonzero? ||
            RecordingStudioApi.configuration.rate_limit_api_period_seconds.to_i
        end
      end

      def rate_limit_identifier
        return "ip:#{request.remote_ip}" if rate_limit_bucket == "api_pre_auth"

        if oauth_rate_limited_path?
          client_id = params[:client_id].to_s.strip
          return "client:#{client_id}" if client_id.present?

          return "ip:#{request.remote_ip}"
        end

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

      def rate_limit_bucket_override = @rate_limit_bucket_override

      def oauth_rate_limited_path?
        request.path.end_with?("/oauth/token")
      end

      def api_rate_limited_path?
        RecordingStudioApi.api_versions.any? do |version|
          request.path.include?("/api/#{version}/") || request.path.end_with?("/api/#{version}")
        end
      end

      def api_read_request?
        api_rate_limited_path? && request.get?
      end

      def rate_limit_redis_client
        require "redis"

        url = RecordingStudioApi.configuration.rate_limit_redis_url.to_s.strip
        @rate_limit_redis_client ||= url.present? ? Redis.new(url: url) : Redis.new
      rescue LoadError
        nil
      end
    end
  end
end
