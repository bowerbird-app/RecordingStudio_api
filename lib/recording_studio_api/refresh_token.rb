# frozen_string_literal: true

require "securerandom"
require_relative "token_digest"

module RecordingStudioApi
  module RefreshToken
    PREFIX = "rsapi_rt"
    TOKEN_PATTERN = /\A#{PREFIX}_[A-Za-z0-9\-_]+\z/

    module_function

    def generate
      token = "#{PREFIX}_#{SecureRandom.urlsafe_base64(48)}"

      {
        token: token,
        digest: TokenDigest.digest(token),
        prefix: token.first(16)
      }
    end

    def valid_format?(token)
      TOKEN_PATTERN.match?(token.to_s)
    end

    def find_by_token(scope, token)
      TokenDigest.find_by_token_digest(scope, token)
    end
  end
end
