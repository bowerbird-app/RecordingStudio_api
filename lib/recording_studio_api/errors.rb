# frozen_string_literal: true

module RecordingStudioApi
  class Error < StandardError; end

  class InvalidActionInputError < Error
    attr_reader :details

    def initialize(message = "Action input is invalid", details: [])
      super(message)
      @details = Array(details)
    end

    # Kept separate from `#details` so a `RecordingStudio::Denial` mixin,
    # which defines its own `#details`, cannot replace the validation list.
    def validation_details
      @details
    end
  end

  class AuthenticationError < Error; end

  class AuthorizationError < Error
    MISSING_REQUEST_PRINCIPAL = "This request has no API client or actor to scope idempotency and pagination"

    def self.for_required_role(role)
      "This action needs a grant with the #{role} role or higher."
    end
  end

  class ConfigurationError < Error; end
  class InvalidPaginationTokenError < Error; end

  class IdempotencyKeyMismatchError < Error
    CODE = "idempotency_key_reused"
    DEFAULT_MESSAGE = "Idempotency key already used with different parameters"

    def initialize(message = DEFAULT_MESSAGE)
      super
    end

    def code
      CODE
    end
  end

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
