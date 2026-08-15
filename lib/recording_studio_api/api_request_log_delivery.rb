# frozen_string_literal: true

module RecordingStudioApi
  # Delivers API request log payloads synchronously, via ActiveJob, or through a
  # process-local batch that flushes to ActiveJob.
  module ApiRequestLogDelivery
    module_function

    def deliver(payload)
      case RecordingStudioApi.configuration.api_request_logging_delivery.to_s
      when "async"
        enqueue([serialize_payload(payload)])
      when "batched"
        ApiRequestLogBatch.push(serialize_payload(payload))
      else
        ApiRequestLog.create!(payload)
      end
    end

    def enqueue(payloads)
      WriteApiRequestLogsJob.perform_later(payloads)
    rescue StandardError => e
      Rails.logger.warn("[RecordingStudioApi] failed to enqueue api request logs: #{e.class}: #{e.message}")
      payloads.each do |payload|
        ApiRequestLog.create!(deserialize_payload(payload))
      end
    end
    private_class_method :enqueue

    def serialize_payload(payload)
      data = payload.transform_keys(&:to_s)
      occurred_at = data["occurred_at"]
      data["occurred_at"] = occurred_at.iso8601(6) if occurred_at.respond_to?(:iso8601)
      data
    end
    private_class_method :serialize_payload

    def deserialize_payload(payload)
      data = payload.transform_keys(&:to_s)
      occurred_at = data["occurred_at"]
      data["occurred_at"] = Time.iso8601(occurred_at) if occurred_at.is_a?(String)
      data.symbolize_keys
    end
    private_class_method :deserialize_payload
  end
end
