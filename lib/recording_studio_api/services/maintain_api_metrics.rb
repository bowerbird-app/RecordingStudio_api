# frozen_string_literal: true

module RecordingStudioApi
  module Services
    # Aggregates recent complete days into daily metrics, then prunes raw request logs
    # and optional daily-metric retention. Intended for a nightly schedule.
    class MaintainApiMetrics
      LOOKBACK_DAYS = 3

      class << self
        def call(lookback_days: LOOKBACK_DAYS)
          new(lookback_days: lookback_days).call
        end
      end

      def initialize(lookback_days: LOOKBACK_DAYS)
        @lookback_days = Integer(lookback_days)
        raise ArgumentError, "lookback_days must be positive" unless @lookback_days.positive?
      end

      def call
        {
          aggregated_dates: aggregate_recent_days!,
          pruned_request_logs: PruneApiRequestLogs.call,
          pruned_daily_metrics: PruneApiDailyMetrics.call
        }
      end

      private

      attr_reader :lookback_days

      def aggregate_recent_days!
        aggregated = []
        lookback_days.downto(1) do |days_ago|
          metric_date = Date.current - days_ago.days
          aggregated << metric_date if AggregateApiRequestLogMetrics.call(metric_date: metric_date)
        end
        aggregated
      end
    end
  end
end
