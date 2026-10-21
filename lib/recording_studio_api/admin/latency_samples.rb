# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    module LatencySamples
      module_function

      def for_day(day:, api_key:)
        date = day.to_date
        samples = from_raw(date, api_key)
        return samples unless samples.empty?

        from_legacy(date, api_key)
      end

      def from_legacy(day, api_key)
        return [] unless ApiDailyLatencyHistogramBucket.table_available?

        ApiDailyLatencyHistogramBucket.where(metric_date: day, api_key: api_key).pluck(:upper_bound_ms, :request_count).flat_map do |bucket, count|
          Array.new(count.to_i, bucket.to_i)
        end
      end

      def from_raw(day, api_key)
        return [] unless ApiRequestLog.table_available?

        start_at = Time.utc(day.year, day.month, day.day)
        ApiRequestLog.where(api_key: api_key).where("occurred_at >= ? AND occurred_at < ?", start_at, start_at + 1.day).pluck(:duration_ms).compact
      end
    end
  end
end
