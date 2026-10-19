# frozen_string_literal: true

module RecordingStudioApi
  module ApiRequestLogDelivery
    module_function

    def deliver(payload)
      case RecordingStudioApi.configuration.api_request_logging_delivery.to_s
      when "async"
        enqueue([serialize_payload(payload)])
      when "batched"
        ApiRequestLogBatch.push(serialize_payload(payload))
      else
        ApiRequestLog.write_payloads!([payload])
      end
    end

    def enqueue(payloads)
      WriteApiRequestLogsJob.perform_later(payloads)
    rescue StandardError => e
      Rails.logger.warn("[RecordingStudioApi] failed to enqueue api request logs: #{e.class}: #{e.message}")
      Array(payloads).each do |payload|
        ApiRequestLog.write_payloads!([payload])
      rescue StandardError => write_error
        Rails.logger.warn("[RecordingStudioApi] api request log write failed: #{write_error.class}: #{write_error.message}")
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
  end
end
