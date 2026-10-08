# frozen_string_literal: true

module RecordingStudioApi
  class Error < StandardError; end

  class InvalidActionInputError < Error
    attr_reader :details

    def initialize(message = "Action input is invalid", details: [])
      super(message)
      @details = Array(details)
    end
  end

  class AuthenticationError < Error; end
  class AuthorizationError < Error; end
  class ConfigurationError < Error; end
  class InvalidPaginationTokenError < Error; end
  class NotFoundError < Error; end
  class UnsupportedActionError < Error; end

  class MethodNotAllowedError < Error
    attr_reader :allowed_http_verbs

    def initialize(message = "Method not allowed", allowed_http_verbs: [])
      super(message)
      @allowed_http_verbs = Array(allowed_http_verbs).map { |verb| verb.to_s.downcase.to_sym }
    end

    def allow_header
      allowed_http_verbs.map { |verb| verb.to_s.upcase }.join(", ")
    end
  end
end
