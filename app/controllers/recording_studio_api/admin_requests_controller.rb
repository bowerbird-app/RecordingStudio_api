# frozen_string_literal: true

module RecordingStudioApi
  class AdminRequestsController < AdminController
    TABLE_LIMIT = 25
    RANGE_LAST_24_HOURS = "last_24_hours"
    REQUEST_STATUS_LISTS = [
      ["Success (2xx)", "success"],
      ["Client errors (4xx)", "client_error"],
      ["Server errors (5xx)", "server_error"]
    ].freeze
    SORT_COLUMNS = {
      "occurred_at" => :occurred_at,
      "request_method" => :request_method,
      "request_path" => :request_path,
      "status_code" => :status_code,
      "remote_ip" => :remote_ip,
      "duration_ms" => :duration_ms,
      "request_id" => :request_id
    }.freeze
    SORT_DIRECTIONS = %w[asc desc].freeze
    GROUP_BY_OPTIONS = [
      %w[Hour hour],
      %w[Day day],
      %w[Week week],
      %w[Month month],
      %w[Year year]
    ].freeze

    def index
      @sort = resolved_sort
      @direction = resolved_direction
      initialize_filters
      load_chart_data
      load_summary_data

      if request.format.json?
        render json: requests_chart_payload
        return
      end

      load_table_data

      return unless turbo_frame_request?

      if dashboard_embed_request?
        render partial: "recording_studio_api/admin_requests/dashboard_chart"
        return
      end

      render partial: "recording_studio_api/admin_requests/content"
    end

    private

    def initialize_filters
      if last_24_hours_range?
        @requests_chart_end_time = Time.current
        @requests_chart_start_time = @requests_chart_end_time - 24.hours
        @requests_chart_start_date = @requests_chart_start_time.to_date
        @requests_chart_end_date = @requests_chart_end_time.to_date
      else
        @requests_chart_start_date = parsed_date(params[:start_date]) || 29.days.ago.to_date
        @requests_chart_end_date = parsed_date(params[:end_date]) || Date.current

        @requests_chart_start_date, @requests_chart_end_date = @requests_chart_end_date, @requests_chart_start_date if @requests_chart_start_date > @requests_chart_end_date

        @requests_chart_start_time = @requests_chart_start_date.beginning_of_day
        @requests_chart_end_time = @requests_chart_end_date.end_of_day
      end

      @requests_chart_status_lists = REQUEST_STATUS_LISTS
      @requests_chart_status = normalized_status
      @requests_chart_group_by_options = GROUP_BY_OPTIONS
      @requests_chart_group_by = last_24_hours_range? ? "hour" : normalized_group_by
    end

    def load_table_data
      @requests_table_base_url = RecordingStudioApi.admin_requests_path(
        controller: self,
        close_url: params[:close_url],
        range: params[:range],
        start_date: @requests_chart_start_date&.iso8601,
        end_date: @requests_chart_end_date&.iso8601,
        status: @requests_chart_status,
        group_by: @requests_chart_group_by,
        sort: @sort,
        direction: @direction
      )

      unless RecordingStudioApi::ApiRequestLog.table_available?
        @request_log_rows = []
        return
      end

      @request_log_rows = filtered_requests_scope
                          .order(current_sort_column => @direction.to_sym, id: @direction.to_sym)
                          .limit(TABLE_LIMIT)
                          .map do |log|
        occurred_at = log.occurred_at || log.created_at

        {
          occurred_at: occurred_at,
          method: log.request_method,
          path: log.request_path,
          status: log.status_code.to_s,
          rate_limited: log.rate_limited? ? "Yes" : "No",
          ip_address: log.remote_ip.to_s.presence || "-",
          duration: "#{log.duration_ms} ms",
          request_id: log.request_id.presence || "-"
        }
      end
    end

    def parsed_date(raw_date)
      return nil if raw_date.blank?

      Date.iso8601(raw_date.to_s)
    rescue ArgumentError
      nil
    end

    def normalized_status
      requested_status = params[:status].to_s
      allowed_statuses = REQUEST_STATUS_LISTS.map { |(_label, value)| value }
      allowed_statuses.include?(requested_status) ? requested_status : nil
    end

    def load_chart_data
      bucket_starts = chart_bucket_starts
      @requests_chart_categories = bucket_starts.map { |bucket_start| chart_bucket_label(bucket_start) }

      unless RecordingStudioApi::ApiRequestLog.table_available?
        @requests_chart_series = Array.new(@requests_chart_categories.length, 0)
        return
      end

      counts_by_bucket = bucket_starts.index_with(0)
      filtered_requests_scope.pluck(:occurred_at).each do |occurred_at|
        bucket_start = chart_bucket_start_for(occurred_at)
        counts_by_bucket[bucket_start] += 1 if counts_by_bucket.key?(bucket_start)
      end

      @requests_chart_series = bucket_starts.map do |bucket_start|
        counts_by_bucket.fetch(bucket_start, 0)
      end
    end

    def load_summary_data
      unless RecordingStudioApi::ApiRequestLog.table_available?
        @requests_chart_total_count = 0
        @requests_chart_previous_total_count = 0
        @requests_chart_percentage_difference = 0.0
        return
      end

      @requests_chart_total_count = filtered_requests_scope.count
      previous_start_time, previous_end_time = previous_period_time_window
      @requests_chart_previous_total_count = filtered_requests_scope_for(occurred_at: previous_start_time...previous_end_time).count
      @requests_chart_percentage_difference = percentage_difference(
        current_total: @requests_chart_total_count,
        previous_total: @requests_chart_previous_total_count
      )
    end

    def normalized_group_by
      requested_group_by = params[:group_by].to_s
      allowed_group_bys = GROUP_BY_OPTIONS.map { |(_label, value)| value }
      allowed_group_bys.include?(requested_group_by) ? requested_group_by : "day"
    end

    def filtered_requests_scope
      filtered_requests_scope_for(occurred_at: @requests_chart_start_time..@requests_chart_end_time)
    end

    def filtered_requests_scope_for(occurred_at:)
      scope = RecordingStudioApi::ApiRequestLog.where(occurred_at: occurred_at)

      case @requests_chart_status
      when "success"
        scope.where(status_code: 200..299)
      when "client_error"
        scope.where(status_code: 400..499)
      when "server_error"
        scope.where(status_code: 500..599)
      else
        scope
      end
    end

    def previous_period_time_window
      if last_24_hours_range?
        previous_end_time = @requests_chart_start_time
        previous_start_time = previous_end_time - 24.hours
      else
        day_count = (@requests_chart_end_date - @requests_chart_start_date).to_i + 1
        previous_end_time = @requests_chart_start_date.beginning_of_day
        previous_start_time = previous_end_time - day_count.days
      end
      [previous_start_time, previous_end_time]
    end

    def percentage_difference(current_total:, previous_total:)
      return 0.0 if current_total.zero? && previous_total.zero?
      return nil if previous_total.zero?

      (((current_total - previous_total).to_f / previous_total) * 100).round(1)
    end

    def requests_chart_payload
      {
        categories: @requests_chart_categories,
        series: @requests_chart_series,
        summary: {
          total_count: @requests_chart_total_count,
          previous_total_count: @requests_chart_previous_total_count,
          percentage_difference: @requests_chart_percentage_difference
        }
      }
    end

    def resolved_sort
      requested_sort = params[:sort].to_s
      SORT_COLUMNS.key?(requested_sort) ? requested_sort : "occurred_at"
    end

    def resolved_direction
      requested_direction = params[:direction].to_s.downcase
      SORT_DIRECTIONS.include?(requested_direction) ? requested_direction : "desc"
    end

    def current_sort_column
      SORT_COLUMNS.fetch(@sort)
    end

    def admin_requests_filter_form_params
      page_nav_close_param.merge(sort: @sort, direction: @direction)
    end
    helper_method :admin_requests_filter_form_params

    def dashboard_embed_request?
      params[:dashboard_embed].to_s == "1"
    end

    def last_24_hours_range?
      params[:range].to_s == RANGE_LAST_24_HOURS
    end

    def chart_bucket_starts
      case @requests_chart_group_by
      when "hour"
        build_time_buckets(
          @requests_chart_start_time.beginning_of_hour,
          @requests_chart_end_time.beginning_of_hour
        ) { |time| time + 1.hour }
      when "week"
        build_time_buckets(
          @requests_chart_start_date.beginning_of_week.to_date,
          @requests_chart_end_date.beginning_of_week.to_date
        ) { |date| date + 1.week }
      when "month"
        build_time_buckets(
          @requests_chart_start_date.beginning_of_month,
          @requests_chart_end_date.beginning_of_month
        ) { |date| date.next_month.beginning_of_month }
      when "year"
        build_time_buckets(
          @requests_chart_start_date.beginning_of_year,
          @requests_chart_end_date.beginning_of_year
        ) { |date| date.next_year.beginning_of_year }
      else
        build_time_buckets(@requests_chart_start_date, @requests_chart_end_date) { |date| date + 1.day }
      end
    end

    def build_time_buckets(start_bucket, end_bucket)
      buckets = []
      current_bucket = start_bucket
      while current_bucket <= end_bucket
        buckets << current_bucket
        current_bucket = yield(current_bucket)
      end
      buckets
    end

    def chart_bucket_start_for(occurred_at)
      case @requests_chart_group_by
      when "hour"
        occurred_at.in_time_zone.beginning_of_hour
      when "week"
        occurred_at.to_date.beginning_of_week.to_date
      when "month"
        occurred_at.to_date.beginning_of_month
      when "year"
        occurred_at.to_date.beginning_of_year
      else
        occurred_at.to_date
      end
    end

    def chart_bucket_label(bucket_start)
      case @requests_chart_group_by
      when "hour"
        bucket_start.strftime("%b %-d %l %p").squish
      when "week"
        "Week of #{bucket_start.strftime('%b %-d')}"
      when "month"
        bucket_start.strftime("%b %Y")
      when "year"
        bucket_start.strftime("%Y")
      else
        bucket_start.strftime("%b %-d")
      end
    end
  end
end
