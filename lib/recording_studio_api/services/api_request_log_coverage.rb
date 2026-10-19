# frozen_string_literal: true

module RecordingStudioApi
  module Services
    class ApiRequestLogCoverage
      Source = Struct.new(:kind, :day, keyword_init: true)

      class << self
        def source_for(day)
          new.source_for(day.to_date)
        end
      end

      def source_for(day)
        return Source.new(kind: :summary, day: day) if covered?(day)
        return Source.new(kind: :raw, day: day) if raw_present?(day)
        return Source.new(kind: :legacy, day: day) if legacy_present?(day)

        Source.new(kind: :gap, day: day)
      end

      def covered?(day)
        connection = LogsRegistration.logging_connection
        RecordingStudioLogs::AggregationRun.fresh?(
          LogsRegistration::REQUEST_COUNTS, [day], nil, connection: connection
        ) && RecordingStudioLogs::AggregationRun.fresh?(
          LogsRegistration::REQUEST_LATENCY, [day], nil, connection: connection
        )
      end

      def raw_present?(day)
        return false unless ApiRequestLog.table_available?

        start_at, finish_at = utc_window(day)
        ApiRequestLog.where("occurred_at >= ? AND occurred_at < ?", start_at, finish_at).exists?
      end

      def legacy_present?(day)
        return false unless ApiDailyMetric.table_available?

        ApiDailyMetric.where(metric_date: day).exists?
      end

      def utc_window(day)
        start_at = Time.utc(day.year, day.month, day.day)
        [start_at, start_at + 1.day]
      end
    end
  end
end
