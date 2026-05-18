# frozen_string_literal: true

module RecordingStudioApi
  class Error < StandardError; end

  class AuthenticationError < Error; end
  class AuthorizationError < Error; end
  class ConfigurationError < Error; end
  class NotFoundError < Error; end
  class UnsupportedActionError < Error; end
end
