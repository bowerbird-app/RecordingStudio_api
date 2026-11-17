# frozen_string_literal: true

require "openssl"

module RecordingStudioApi
  # Digests for API credentials and OAuth access tokens.
  #
  # Writes and checks use HMAC-SHA256 with a pepper.
  module TokenDigest
    module_function

    def digest(token)
      peppered_digest(token)
    end

    def peppered_digest(token)
      OpenSSL::HMAC.hexdigest("SHA256", pepper, token.to_s)
    end

    def matches?(stored_digest, token)
      return false if stored_digest.blank?

      candidate = peppered_digest(token)
      return false unless stored_digest.bytesize == candidate.bytesize

      ActiveSupport::SecurityUtils.secure_compare(stored_digest, candidate)
    end

    def find_by_token_digest(scope, token)
      scope.find_by(token_digest: digest(token))
    end

    def pepper
      configured = RecordingStudioApi.configuration.token_digest_pepper
      return configured.to_s if configured.present?
      return Rails.application.secret_key_base.to_s if defined?(Rails) && Rails.application&.secret_key_base.present?

      raise RecordingStudioApi::ConfigurationError,
            "token_digest_pepper is required (set RECORDING_STUDIO_API_TOKEN_DIGEST_PEPPER " \
            "or config.token_digest_pepper, or ensure Rails.application.secret_key_base is present)"
    end
  end
end
