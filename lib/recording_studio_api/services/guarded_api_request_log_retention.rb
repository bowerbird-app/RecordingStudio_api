# frozen_string_literal: true

module RecordingStudioApi
  module Services
    class GuardedApiRequestLogRetention
      class << self
        def call(before: nil)
          new(before: before).call
        end
      end

      def initialize(before:)
        @before = before
      end

      def call
        return 0 unless ApiRequestLog.table_available?

        LogsRegistration.register!
        log = RecordingStudioLogs.registry.log_for(LogsRegistration::SOURCE_MODEL)
        return 0 if log.nil?
        return 0 if log.indefinite? && before.blank?

        connection = LogsRegistration.logging_connection
        covered, waiting = fresh_days(log, connection)
        return 0 if covered.empty? && waiting.any?
        return 0 if covered.empty?

        RecordingStudioLogs::Lock.with(connection, *RecordingStudioLogs::Lock.names_for(
          RecordingStudioLogs.registry.aggregations_for(log), covered
        )) do
          RecordingStudioLogs::Lock.hold_writes(connection, log.table_name)
          current, = fresh_days(log, connection)
          deletable = current & covered
          return 0 if deletable.empty?

          RecordingStudioLogs::Retention::RawRows.delete_days(connection, log, cutoff(log), deletable)
        end
        covered.size
      end

      private

      attr_reader :before

      def fresh_days(log, connection)
        RecordingStudioLogs::Retention::RawRows.expired_days(connection, log, cutoff(log)).partition do |day|
          day_fresh?(log, day, connection)
        end
      end

      def day_fresh?(log, day, connection)
        watermark = RecordingStudioLogs::Retention::RawRows.newest_for_days(
          connection, log, cutoff(log), [day]
        )
        RecordingStudioLogs::AggregationRun.log_fresh?(log, [day], watermark, connection: connection)
      end

      def cutoff(log)
        return before if before.present?

        Time.now.utc - log.retention
      end
    end
  end
end
