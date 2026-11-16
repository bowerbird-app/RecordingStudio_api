# frozen_string_literal: true

module RecordingStudioApi
  # Holds the controller for the current collection read so the index
  # service can call fresh_when before it loads rows.
  module CollectionHttp
    THREAD_KEY = :recording_studio_api_collection_http

    def self.with(controller)
      previous = Thread.current[THREAD_KEY]
      Thread.current[THREAD_KEY] = controller
      yield
    ensure
      Thread.current[THREAD_KEY] = previous
    end

    def self.controller
      Thread.current[THREAD_KEY]
    end
  end
end
