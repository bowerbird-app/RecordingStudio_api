# frozen_string_literal: true

require "digest"
require "json"

module RecordingStudioApi
  # Redis-backed request idempotency for mutating resource operations.
  # Keys are scoped to API + client so one client cannot replay another's response.
  class IdempotencyStore
    DEFAULT_TTL_SECONDS = 24 * 60 * 60

    class << self
      def fetch(api:, client_id:, key:)
        return nil if key.blank? || client_id.blank?

        raw = redis&.get(redis_key(api: api, client_id: client_id, key: key))
        return nil if raw.blank?

        JSON.parse(raw)
      rescue JSON::ParserError => e
        Rails.logger.warn("[RecordingStudioApi] idempotency fetch failed: #{e.class}: #{e.message}")
        nil
      rescue StandardError => e
        raise unless redis_error?(e)

        Rails.logger.warn("[RecordingStudioApi] idempotency fetch failed: #{e.class}: #{e.message}")
        nil
      end

      def write(api:, client_id:, key:, payload:, status:, ttl: DEFAULT_TTL_SECONDS)
        return if key.blank? || client_id.blank?

        redis&.set(
          redis_key(api: api, client_id: client_id, key: key),
          JSON.generate("json" => payload, "status" => status),
          ex: ttl.to_i
        )
      rescue StandardError => e
        raise unless redis_error?(e)

        Rails.logger.warn("[RecordingStudioApi] idempotency write failed: #{e.class}: #{e.message}")
        nil
      end

      def redis_key(api:, client_id:, key:)
        namespace = RecordingStudioApi.configuration.rate_limit_redis_namespace.presence || "recording_studio_api"
        "#{namespace}:idempotency:#{api}:#{client_id}:#{Digest::SHA256.hexdigest(key.to_s)}"
      end

      def redis
        RecordingStudioApi::Concerns::RateLimiting.redis_client
      end

      def redis_error?(error)
        defined?(Redis) && error.is_a?(Redis::BaseError)
      end
    end
  end
end
