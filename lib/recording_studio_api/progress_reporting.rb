# frozen_string_literal: true

module RecordingStudioApi
  # Optional progress callbacks on handler contexts.
  #
  # A reporter is any object that responds to:
  #
  #   progress(current:, total:, message:)
  #   cancelled?
  #
  # This gem only forwards those messages. It does not know about MCP, SSE,
  # JSON-RPC, or progress tokens. REST construction leaves +progress_reporter+
  # as +nil+, so existing handlers keep working.
  module ProgressReporting
    def progress(current:, total: nil, message: nil)
      return if progress_reporter.nil?

      progress_reporter.progress(current: current, total: total, message: message)
    end

    def cancelled?
      return false if progress_reporter.nil?

      progress_reporter.cancelled?
    end
  end
end
