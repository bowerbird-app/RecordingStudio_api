# frozen_string_literal: true

require "securerandom"
require_relative "token_digest"

module RecordingStudioApi
  module OauthClientSecret
    PREFIX = "rsapi_cs"

    module_function

    def generate
      token = "#{PREFIX}_#{SecureRandom.urlsafe_base64(32)}"

      {
        token: token,
        digest: TokenDigest.digest(token)
      }
    end

    def generate_client_id
      "rsapi_oc_#{SecureRandom.hex(16)}"
    end
  end
end
