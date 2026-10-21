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

      METRIC_COLUMNS = %w[
        metric_date api_key route_name request_method status_class
        request_count rate_limited_count client_error_count server_error_count
        duration_count duration_sum_ms duration_max_ms
      ].freeze

      def covered?(day)
        log = RecordingStudioLogs.registry.log_for(LogsRegistration::SOURCE_MODEL)
        return false if log.nil?

        connection = LogsRegistration.logging_connection
        watermark = RecordingStudioLogs::Retention::RawRows.newest_for_days(
          connection, log, utc_window(day).last, [day]
        )
        RecordingStudioLogs::AggregationRun.log_fresh?(log, [day], watermark, connection: connection)
      end

      def metric_relation(relation)
        grouped = metric_candidate_days(relation).group_by { |day| source_for(day).kind }
        summary_days = grouped.fetch(:summary, [])
        legacy_days = grouped.fetch(:legacy, [])
        summary = select_metric_columns(relation).where(metric_date: summary_days)

        return summary if legacy_days.empty? || !ApiDailyMetric.table_available?

        legacy = select_metric_columns(ApiDailyMetric.all).where(metric_date: legacy_days)
        union_metric_relation(relation.klass, summary, legacy, summary_days)
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

      private

      def metric_candidate_days(relation)
        days = []
        days.concat(relation.unscope(:select).distinct.pluck(:metric_date)) if relation.klass.table_available?
        days.concat(ApiDailyMetric.distinct.pluck(:metric_date)) if ApiDailyMetric.table_available?
        days.compact.map(&:to_date).uniq
      end

      def select_metric_columns(rel)
        connection = rel.klass.connection
        columns = METRIC_COLUMNS.map do |name|
          "#{rel.klass.quoted_table_name}.#{connection.quote_column_name(name)}"
        end
        rel.unscope(:select).select(columns.join(", "))
      end

      def union_metric_relation(klass, summary, legacy, summary_days)
        sql = if summary_days.empty?
                legacy.to_sql
              else
                "#{summary.to_sql} UNION ALL #{legacy.to_sql}"
              end
        klass.from("(#{sql}) AS #{klass.quoted_table_name}")
      end
    end
  end
end
