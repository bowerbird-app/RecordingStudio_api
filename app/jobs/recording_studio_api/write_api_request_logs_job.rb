# frozen_string_literal: true

module RecordingStudioApi
  class WriteApiRequestLogsJob < ActiveJob::Base
    queue_as :recording_studio_api_logging

    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    def perform(payloads)
      ApiRequestLog.write_payloads!(payloads)
    end
  end
end
