# frozen_string_literal: true

require "recording_studio_api/version"
require "recording_studio_api/engine"
require "recording_studio_api/configuration"
require "recording_studio_api/services/base_service"
require "recording_studio_api/services/example_service"

module RecordingStudioApi
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
    end
  end
end
