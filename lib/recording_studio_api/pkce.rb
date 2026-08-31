# frozen_string_literal: true

require "digest"
require "base64"

module RecordingStudioApi
  module Pkce
    S256 = "S256"
    VERIFIER_PATTERN = /\A[A-Za-z0-9\-._~]{43,128}\z/

    module_function

    def s256_challenge(verifier)
      Base64.urlsafe_encode64(Digest::SHA256.digest(verifier.to_s), padding: false)
    end

    def valid_verifier?(verifier)
      VERIFIER_PATTERN.match?(verifier.to_s)
    end

    def s256_matches?(verifier, challenge)
      return false unless valid_verifier?(verifier)
      return false if challenge.blank?

      computed = s256_challenge(verifier)
      return false unless computed.bytesize == challenge.to_s.bytesize

      ActiveSupport::SecurityUtils.secure_compare(computed, challenge.to_s)
    end
  end
end
