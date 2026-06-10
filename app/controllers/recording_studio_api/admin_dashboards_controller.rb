# frozen_string_literal: true

module RecordingStudioApi
  class AdminDashboardsController < AdminController
    def show
      hourly_points = build_log_chart_points(buckets: hourly_buckets(24)) do |occurred_at|
        occurred_at.in_time_zone.beginning_of_hour
      end
      @log_chart_categories = hourly_points.map { |point| point[:time].hour.to_s }
      @log_chart_series = hourly_points.map { |point| point[:count] }
      @log_volume_last_24_hours = hourly_points.sum { |point| point[:count] }

      daily_points = build_log_chart_points(buckets: daily_buckets(30)) do |occurred_at|
        occurred_at.in_time_zone.beginning_of_day
      end
      @log_chart_categories_last_30_days = daily_points.map { |point| point[:time].strftime("%b %-d") }
      @log_chart_series_last_30_days = daily_points.map { |point| point[:count] }
      @log_volume_last_30_days = daily_points.sum { |point| point[:count] }

      rate_limited_daily_points = build_log_chart_points(
        buckets: daily_buckets(30),
        scope: rate_limited_logs_scope
      ) do |occurred_at|
        occurred_at.in_time_zone.beginning_of_day
      end
      @rate_limited_chart_categories_last_30_days = rate_limited_daily_points.map { |point| point[:time].strftime("%b %-d") }
      @rate_limited_chart_series_last_30_days = rate_limited_daily_points.map { |point| point[:count] }
      @rate_limited_volume_last_30_days = rate_limited_daily_points.sum { |point| point[:count] }

      @last_24_hours_requests_path = RecordingStudioApi.admin_requests_path(
        controller: self,
        close_url: request.fullpath,
        start_date: 1.day.ago.to_date.iso8601,
        end_date: Date.current.iso8601
      )
      @last_30_days_requests_path = RecordingStudioApi.admin_requests_path(
        controller: self,
        close_url: request.fullpath,
        start_date: 29.days.ago.to_date.iso8601,
        end_date: Date.current.iso8601
      )
    end

    private

    def build_log_chart_points(buckets:, scope: RecordingStudioApi::ApiRequestLog.all)
      return buckets.map { |time| chart_point(time, 0) } unless RecordingStudioApi::ApiRequestLog.table_available?

      counts_by_bucket = buckets.index_with(0)
      counts_by_hour = scope.where(
        occurred_at: buckets.first..Time.current
      ).pluck(:occurred_at).each_with_object(counts_by_bucket) do |occurred_at, counts|
        bucket_key = yield(occurred_at)
        counts[bucket_key] += 1 if counts.key?(bucket_key)
      end

      buckets.map { |time| chart_point(time, counts_by_hour[time]) }
    end

    def hourly_buckets(size)
      current_hour = Time.current.in_time_zone.beginning_of_hour
      (size - 1).downto(0).map { |offset| current_hour - offset.hours }
    end

    def daily_buckets(size)
      current_day = Time.current.in_time_zone.beginning_of_day
      (size - 1).downto(0).map { |offset| current_day - offset.days }
    end

    def chart_point(time, count)
      {
        time: time,
        label: time.strftime("%H:%M"),
        count: count
      }
    end

    def rate_limited_logs_scope
      scope = RecordingStudioApi::ApiRequestLog.where(rate_limited: true)
      scope.or(RecordingStudioApi::ApiRequestLog.where(status_code: 429))
    end
  end
end