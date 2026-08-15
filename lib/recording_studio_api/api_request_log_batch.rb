# frozen_string_literal: true

module RecordingStudioApi
  # Process-local buffer used when api_request_logging_delivery = "batched".
  module ApiRequestLogBatch
    DEFAULT_BATCH_SIZE = 25

    module_function

    def push(payload)
      mutex.synchronize do
        buffer << payload
        flush_locked! if buffer.size >= batch_size
      end
    end

    def flush!
      mutex.synchronize { flush_locked! }
    end

    def clear!
      mutex.synchronize { buffer.clear }
    end

    def buffer_size
      mutex.synchronize { buffer.size }
    end

    def batch_size
      configured = RecordingStudioApi.configuration.api_request_logging_batch_size.to_i
      configured.positive? ? configured : DEFAULT_BATCH_SIZE
    end
    private_class_method :batch_size

    def buffer
      @buffer ||= []
    end
    private_class_method :buffer

    def mutex
      @mutex ||= Mutex.new
    end
    private_class_method :mutex

    def flush_locked!
      return if buffer.empty?

      payloads = buffer.shift(buffer.size)
      WriteApiRequestLogsJob.perform_later(payloads)
    rescue StandardError => e
      Rails.logger.warn("[RecordingStudioApi] failed to enqueue batched api request logs: #{e.class}: #{e.message}")
      payloads.each do |payload|
        ApiRequestLog.create!(payload)
      rescue StandardError => write_error
        Rails.logger.warn("[RecordingStudioApi] api request log write failed: #{write_error.class}: #{write_error.message}")
      end
    end
    private_class_method :flush_locked!
  end
end
