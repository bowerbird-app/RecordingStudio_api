# frozen_string_literal: true

require "digest"
require "securerandom"

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
      Digest::SHA256.hexdigest(token.to_s)
    end
  end
end