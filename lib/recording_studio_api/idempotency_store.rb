# frozen_string_literal: true

require "digest"
require "json"

module RecordingStudioApi
  # Keys include API and client so one client cannot replay another's response.
  class IdempotencyStore
    DEFAULT_TTL_SECONDS = 24 * 60 * 60

    class << self
      def fetch(api:, client_id:, key:, fingerprint: nil)
        return nil if key.blank? || client_id.blank?

        raw = read_raw(storage_key(api: api, client_id: client_id, key: key))
        return nil if raw.blank?

        stored = JSON.parse(raw)
        assert_fingerprint!(stored, fingerprint)
        stored
      rescue JSON::ParserError => e
        Rails.logger.warn("[RecordingStudioApi] idempotency fetch failed: #{e.class}: #{e.message}")
        nil
      end

      def write(api:, client_id:, key:, payload:, status:, ttl: DEFAULT_TTL_SECONDS, fingerprint: nil)
        return if key.blank? || client_id.blank?

        record = { "json" => payload, "status" => status }
        record["fingerprint"] = fingerprint.to_s if fingerprint.present?
        write_raw(
          storage_key(api: api, client_id: client_id, key: key),
          JSON.generate(record),
          ttl.to_i
        )
      end

      def fingerprint(method:, path:, params: {})
        Digest::SHA256.hexdigest(canonical_request(method, path, params))
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

      def assert_fingerprint!(stored, fingerprint)
        return unless stored.is_a?(Hash)
        return if fingerprint.blank?

        stored_fingerprint = stored["fingerprint"].to_s
        return if stored_fingerprint.blank?
        return if stored_fingerprint == fingerprint.to_s

        raise IdempotencyKeyMismatchError
      end

      def canonical_request(method, path, params)
        [
          method.to_s.upcase,
          path.to_s,
          JSON.generate(normalize_fingerprint_value(params || {}))
        ].join("\n")
      end

      def normalize_fingerprint_value(value)
        case value
        when ActionController::Parameters
          normalize_fingerprint_value(value.to_unsafe_h)
        when Hash
          value.each_with_object({}) do |(key, child), normalized|
            normalized[key.to_s] = normalize_fingerprint_value(child)
          end.sort.to_h
        when Array
          value.map { |child| normalize_fingerprint_value(child) }
        when Symbol
          value.to_s
        else
          value
        end
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
        return unless process_local_cache?

        fallback_mutex.synchronize do
          return if @fallback_warned

          @fallback_warned = true
          detail = error ? "#{error.class}: #{error.message}" : "Redis client is missing"
          Rails.logger.warn(durability_warning(detail))
        end
      end

      def process_local_cache?
        store = Rails.cache
        store.is_a?(ActiveSupport::Cache::NullStore) || store.is_a?(ActiveSupport::Cache::MemoryStore)
      end

      def durability_warning(detail)
        store_name = Rails.cache.class.name
        local_detail = if Rails.cache.is_a?(ActiveSupport::Cache::NullStore)
                         "#{store_name}, which is process-local and stores nothing"
                       else
                         "#{store_name}, which is process-local and keeps keys in this process only"
                       end
        "[RecordingStudioApi] idempotency keys are not durable. Redis is unavailable (#{detail}) and Rails.cache is #{local_detail}."
      end

      def fallback_mutex
        @fallback_mutex ||= Mutex.new
      end
    end
  end
end
