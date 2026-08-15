# frozen_string_literal: true

require "securerandom"
require_relative "token_digest"

module RecordingStudioApi
  module OauthAccessToken
    PREFIX = "rsapi_at".freeze
    TOKEN_PATTERN = /\A#{PREFIX}_[A-Za-z0-9\-_]+\z/.freeze

    module_function

    def generate
      token = "#{PREFIX}_#{SecureRandom.urlsafe_base64(48)}"

      {
        token: token,
        digest: digest(token),
        prefix: token.first(18)
      }
    end

    def valid_format?(token)
      TOKEN_PATTERN.match?(token.to_s)
    end

    def digest(token)
      TokenDigest.digest(token)
    end

    def digest_candidates(token)
      TokenDigest.digest_candidates(token)
    end

    def find_by_token(scope, token)
      TokenDigest.find_by_token_digest(scope, token)
    end

    def rehash_if_legacy!(record, token)
      TokenDigest.rehash_if_legacy!(record, token)
    end
  end
end
