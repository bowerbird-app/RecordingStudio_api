# frozen_string_literal: true

require "digest"
require "json"

module RecordingStudioApi
  # Keys include API and client so one client cannot replay another's response.
  class IdempotencyStore
    DEFAULT_TTL_SECONDS = 24 * 60 * 60

    class << self
      def fetch(api:, client_id:, key:)
        return nil if key.blank? || client_id.blank?

        raw = read_raw(storage_key(api: api, client_id: client_id, key: key))
        return nil if raw.blank?

        JSON.parse(raw)
      rescue JSON::ParserError => e
        Rails.logger.warn("[RecordingStudioApi] idempotency fetch failed: #{e.class}: #{e.message}")
        nil
      end

      def write(api:, client_id:, key:, payload:, status:, ttl: DEFAULT_TTL_SECONDS)
        return if key.blank? || client_id.blank?

        write_raw(
          storage_key(api: api, client_id: client_id, key: key),
          JSON.generate("json" => payload, "status" => status),
          ttl.to_i
        )
      end

      def redis_key(api:, client_id:, key:)
        storage_key(api: api, client_id: client_id, key: key)
      end

      def redis
        RecordingStudioApi::Concerns::RateLimiting.redis_client
      end

      def redis_error?(error)
        defined?(Redis) && error.is_a?(Redis::BaseError)
      end

      def reset_fallback_notice!
        fallback_mutex.synchronize { @fallback_warned = false }
      end

      private

      def storage_key(api:, client_id:, key:)
        namespace = RecordingStudioApi.configuration.rate_limit_redis_namespace.presence || "recording_studio_api"
        "#{namespace}:idempotency:#{api}:#{client_id}:#{Digest::SHA256.hexdigest(key.to_s)}"
      end

      def read_raw(key)
        client = redis
        if client
          begin
            return client.get(key)
          rescue StandardError => e
            raise unless redis_error?(e)

            warn_fallback(e)
          end
        else
          warn_fallback(nil)
        end

        Rails.cache.read(key)
      end

      def write_raw(key, blob, ttl)
        client = redis
        if client
          begin
            client.set(key, blob, nx: true, ex: ttl)
            return
          rescue StandardError => e
            raise unless redis_error?(e)

            warn_fallback(e)
          end
        else
          warn_fallback(nil)
        end

        Rails.cache.write(key, blob, expires_in: ttl, unless_exist: true)
      end

      def warn_fallback(error)
        fallback_mutex.synchronize do
          return if @fallback_warned

          @fallback_warned = true
          detail = error ? "#{error.class}: #{error.message}" : "Redis client is missing"
          Rails.logger.warn(
            "[RecordingStudioApi] idempotency is using Rails.cache because Redis is unavailable (#{detail})"
          )
        end
      end

      def fallback_mutex
        @fallback_mutex ||= Mutex.new
      end
    end
  end
end
