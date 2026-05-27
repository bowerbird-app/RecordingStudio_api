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
end
