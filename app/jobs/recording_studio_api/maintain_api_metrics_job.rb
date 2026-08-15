# frozen_string_literal: true

module RecordingStudioApi
  class MaintainApiMetricsJob < ActiveJob::Base
    queue_as :recording_studio_api_metrics

    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    def perform(lookback_days: Services::MaintainApiMetrics::LOOKBACK_DAYS)
      result = Services::MaintainApiMetrics.call(lookback_days: lookback_days)
      Rails.logger.info(
        "[RecordingStudioApi] MaintainApiMetricsJob " \
        "aggregated=#{Array(result[:aggregated_dates]).map(&:iso8601).join(',')} " \
        "pruned_request_logs=#{result[:pruned_request_logs]} " \
        "pruned_daily_metrics=#{result[:pruned_daily_metrics]}"
      )
      result
    end
  end
end
