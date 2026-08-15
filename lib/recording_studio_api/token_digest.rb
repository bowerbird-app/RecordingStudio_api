# frozen_string_literal: true

require "digest"
require "openssl"

module RecordingStudioApi
  # Digests for API credentials and OAuth access tokens.
  #
  # New writes use HMAC-SHA256 with a pepper. During cutover, verification also
  # accepts legacy unsalted SHA256 digests when token_digest_legacy_verify is on.
  module TokenDigest
    module_function

    def digest(token)
      peppered_digest(token)
    end

    def legacy_digest(token)
      Digest::SHA256.hexdigest(token.to_s)
    end

    def peppered_digest(token)
      OpenSSL::HMAC.hexdigest("SHA256", pepper, token.to_s)
    end

    def digest_candidates(token)
      candidates = [peppered_digest(token)]
      candidates << legacy_digest(token) if RecordingStudioApi.configuration.token_digest_legacy_verify
      candidates.uniq
    end

    def matches?(stored_digest, token)
      return false if stored_digest.blank?

      matches = false
      digest_candidates(token).each do |candidate|
        next unless stored_digest.bytesize == candidate.bytesize

        matches |= ActiveSupport::SecurityUtils.secure_compare(stored_digest, candidate)
      end
      matches
    end

    def find_by_token_digest(scope, token)
      digest_candidates(token).each do |candidate|
        record = scope.find_by(token_digest: candidate)
        return record if record
      end
      nil
    end

    def rehash_if_legacy!(record, token)
      return unless RecordingStudioApi.configuration.token_digest_legacy_verify
      return if record.nil? || token.blank?
      return unless record.respond_to?(:token_digest) && record.respond_to?(:update_column)

      peppered = peppered_digest(token)
      return if record.token_digest == peppered
      return unless record.token_digest == legacy_digest(token)

      record.update_column(:token_digest, peppered)
    rescue ActiveRecord::ActiveRecordError
      nil
    end

    def pepper
      configured = RecordingStudioApi.configuration.token_digest_pepper
      return configured.to_s if configured.present?
      if defined?(Rails) && Rails.application&.secret_key_base.present?
        return Rails.application.secret_key_base.to_s
      end

      raise RecordingStudioApi::ConfigurationError,
            "token_digest_pepper is required (set RECORDING_STUDIO_API_TOKEN_DIGEST_PEPPER " \
            "or config.token_digest_pepper, or ensure Rails.application.secret_key_base is present)"
    end
  end
end
