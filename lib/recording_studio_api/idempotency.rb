# frozen_string_literal: true

require "digest"
require "json"

module RecordingStudioApi
  module Idempotency
    SKIP_INPUT = Object.new
    private_constant :SKIP_INPUT

    class << self
      def replay(api:, client_id:, key:, action: nil, recording_id: nil, input: SKIP_INPUT, fingerprint: nil)
        return yield if key.blank?

        digest = fingerprint.presence || fingerprint_for(input)
        stored = IdempotencyStore.fetch(
          api: api,
          client_id: client_id,
          key: storage_key(key, action: action, recording_id: recording_id),
          fingerprint: digest
        )
        if stored.present?
          return {
            json: stored.fetch("json"),
            status: stored.fetch("status", "ok").to_sym
          }
        end

        result = yield
        remember(api, client_id, key, action, recording_id, digest, result)
        result
      end

      def client_id(api_client:, actor:)
        return api_client.id if api_client

        type_name = actor_type_name(actor)
        identifier = actor.id if actor.respond_to?(:id)
        raise AuthorizationError, AuthorizationError::MISSING_REQUEST_PRINCIPAL if type_name.blank? || identifier.blank?

        "actor:#{type_name}:#{identifier}"
      end

      private

      def fingerprint_for(input)
        return if input.equal?(SKIP_INPUT)

        Digest::SHA256.hexdigest(JSON.generate(canonicalize(input)))
      end

      def storage_key(key, action:, recording_id:)
        return key.to_s if action.nil? && recording_id.nil?

        JSON.generate([action.to_s, recording_id.to_s, key.to_s])
      end

      def remember(api, client_id, key, action, recording_id, fingerprint, result)
        return unless success_result?(result)

        IdempotencyStore.write(
          api: api,
          client_id: client_id,
          key: storage_key(key, action: action, recording_id: recording_id),
          payload: json_from(result),
          status: status_from(result).to_s,
          fingerprint: fingerprint
        )
      end

      def success_result?(result)
        return false unless result.is_a?(Hash)
        return false unless result.key?(:json) || result.key?("json")

        code = http_status_code(status_from(result))
        code >= 200 && code < 300
      rescue ArgumentError
        false
      end

      def http_status_code(status)
        return status if status.is_a?(Integer)

        name = status.to_s
        name = "unprocessable_content" if name == "unprocessable_entity"
        Rack::Utils.status_code(name.to_sym)
      end

      def json_from(result)
        result.key?(:json) ? result[:json] : result["json"]
      end

      def status_from(result)
        result[:status] || result["status"] || :ok
      end

      def canonicalize(value)
        return canonicalize_hash(value) if value.is_a?(Hash) || parameters?(value)
        return value.map { |entry| canonicalize(entry) } if value.is_a?(Array)
        return value.to_s if value.is_a?(Symbol)

        value
      end

      def canonicalize_hash(value)
        hash = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value.to_h
        hash.each_with_object({}) do |(entry_key, entry), memo|
          memo[entry_key.to_s] = canonicalize(entry)
        end.sort.to_h
      end

      def parameters?(value)
        defined?(ActionController::Parameters) && value.is_a?(ActionController::Parameters)
      end

      def actor_type_name(actor)
        return if actor.blank?

        klass = actor.class
        return klass.polymorphic_name if klass.respond_to?(:polymorphic_name)

        klass.name
      end
    end
  end
end
