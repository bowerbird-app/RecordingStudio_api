# frozen_string_literal: true

namespace :recording_studio_api do
  namespace :api_metrics do
    desc "Aggregate recent API request logs into daily metrics"
    task aggregate: :environment do
      RecordingStudioApi::Services::MaintainApiMetrics::LOOKBACK_DAYS.downto(1) do |days_ago|
        RecordingStudioApi::Services::AggregateApiRequestLogMetrics.call(metric_date: Date.current - days_ago.days)
      end
    end

    desc "Prune API request logs and daily metrics past configured retention"
    task prune: :environment do
      pruned_logs = RecordingStudioApi::Services::PruneApiRequestLogs.call
      pruned_metrics = RecordingStudioApi::Services::PruneApiDailyMetrics.call
      puts "Pruned #{pruned_logs} request log rows and #{pruned_metrics} daily metric rows"
    end

    desc "Aggregate recent days, then prune request logs and daily metrics"
    task maintain: :environment do
      result = RecordingStudioApi::Services::MaintainApiMetrics.call
      puts(
        "Aggregated #{result[:aggregated_dates].map(&:iso8601).join(', ')}; " \
        "pruned #{result[:pruned_request_logs]} request log rows and " \
        "#{result[:pruned_daily_metrics]} daily metric rows"
      )
    end

    desc "Enqueue MaintainApiMetricsJob for a configured ActiveJob backend"
    task enqueue_maintain: :environment do
      RecordingStudioApi::MaintainApiMetricsJob.perform_later
      puts "Enqueued RecordingStudioApi::MaintainApiMetricsJob"
    end
  end
end
