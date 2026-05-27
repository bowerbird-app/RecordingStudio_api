# frozen_string_literal: true

module RecordingStudioApi
  class AdminDashboardsController < AdminController
    def show
      @log_chart_points = build_log_chart_points
      @log_volume_last_24_hours = @log_chart_points.sum { |point| point[:count] }
      @log_peak_hour = @log_chart_points.max_by { |point| point[:count] }
    end

    private

    def build_log_chart_points
      buckets = hourly_buckets
      return buckets.map { |time| chart_point(time, 0) } unless RecordingStudioApi::ApiRequestLog.table_available?

      counts_by_hour = RecordingStudioApi::ApiRequestLog.where(
        occurred_at: buckets.first..Time.current
      ).pluck(:occurred_at).each_with_object(Hash.new(0)) do |occurred_at, counts|
        counts[occurred_at.in_time_zone.beginning_of_hour] += 1
      end

      buckets.map { |time| chart_point(time, counts_by_hour[time]) }
    end

    def hourly_buckets
      current_hour = Time.current.in_time_zone.beginning_of_hour
      23.downto(0).map { |offset| current_hour - offset.hours }
    end

    def chart_point(time, count)
      {
        time: time,
        label: time.strftime("%H:%M"),
        count: count
      }
    end
  end
end