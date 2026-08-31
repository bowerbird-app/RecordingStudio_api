# frozen_string_literal: true

require "securerandom"
require_relative "token_digest"

module RecordingStudioApi
  module AuthorizationCode
    PREFIX = "rsapi_ac"
    TOKEN_PATTERN = /\A#{PREFIX}_[A-Za-z0-9\-_]+\z/

    module_function

    def generate
      token = "#{PREFIX}_#{SecureRandom.urlsafe_base64(32)}"

      {
        token: token,
        digest: TokenDigest.digest(token)
      }
    end

    def valid_format?(token)
      TOKEN_PATTERN.match?(token.to_s)
    end

    def find_by_token(scope, token)
      TokenDigest.digest_candidates(token).each do |candidate|
        record = scope.find_by(code_digest: candidate)
        return record if record
      end
      nil
    end
  end
end
