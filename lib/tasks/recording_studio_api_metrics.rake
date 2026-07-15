# frozen_string_literal: true

namespace :recording_studio_api do
  namespace :api_metrics do
    task aggregate: :environment do
      3.downto(1) do |days_ago|
        RecordingStudioApi::Services::AggregateApiRequestLogMetrics.call(metric_date: Date.current - days_ago.days)
      end
    end

    task prune: :environment do
      RecordingStudioApi::Services::PruneApiRequestLogs.call
    end

    task maintain: %i[aggregate prune]
  end
end