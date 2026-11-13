# frozen_string_literal: true

module RecordingStudioApi
  class Configuration
    # Rate-limit number and flag checks for Configuration#validate!.
    module RateLimitValidation
      private

      def validate_rate_limit_check_fail_closed!
        return if [true, false].include?(rate_limit_check_fail_closed)

        raise ConfigurationError, "rate_limit_check_fail_closed must be true or false"
      end

      def validate_enabled_rate_limits!
        validate_rate_limit!(:oauth, rate_limit_oauth_requests, rate_limit_oauth_period_seconds) if rate_limit_oauth_enabled
        validate_rate_limit!(:api_pre_auth, rate_limit_api_pre_auth_requests, rate_limit_api_pre_auth_period_seconds) if rate_limit_api_pre_auth_enabled
        return unless rate_limit_api_enabled

        validate_rate_limit!(:api_read, effective_rate_limit_value(rate_limit_api_read_requests, rate_limit_api_requests), effective_rate_limit_value(rate_limit_api_read_period_seconds, rate_limit_api_period_seconds))
        validate_rate_limit!(:api_write, effective_rate_limit_value(rate_limit_api_write_requests, rate_limit_api_requests), effective_rate_limit_value(rate_limit_api_write_period_seconds, rate_limit_api_period_seconds))
      end

      def effective_rate_limit_value(primary, fallback)
        primary.to_i.nonzero? || fallback
      end

      def validate_rate_limit!(bucket, requests, period)
        raise ConfigurationError, "rate_limit_#{bucket}_requests must be positive when rate limiting is enabled" unless positive_number?(requests)
        raise ConfigurationError, "rate_limit_#{bucket}_period_seconds must be positive when rate limiting is enabled" unless positive_number?(period)
      end
    end
  end
end
