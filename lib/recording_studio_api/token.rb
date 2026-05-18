# frozen_string_literal: true

require "digest"
require "securerandom"

module RecordingStudioApi
  module Token
    PREFIX = "rsapi".freeze
    TOKEN_PATTERN = /\A#{PREFIX}_(?<public_id>[a-f0-9]+)\.(?<secret>[A-Za-z0-9\-_]+)\z/.freeze

    module_function

    def generate
      public_id = SecureRandom.hex(8)
      secret = SecureRandom.urlsafe_base64(32)
      token = "#{PREFIX}_#{public_id}.#{secret}"

      {
        public_id: public_id,
        secret: secret,
        token: token,
        digest: digest(token),
        prefix: token.first(12)
      }
    end

    def parse(token)
      match = TOKEN_PATTERN.match(token.to_s)
      return if match.nil?

      {
        public_id: match[:public_id],
        secret: match[:secret],
        token: token.to_s
      }
    end

    def digest(token)
      Digest::SHA256.hexdigest(token.to_s)
    end
  end
end
