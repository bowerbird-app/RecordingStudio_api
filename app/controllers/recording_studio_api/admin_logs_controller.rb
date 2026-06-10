# frozen_string_literal: true

module RecordingStudioApi
  class AdminLogsController < AdminController
    PER_PAGE = 25
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

    def index
      @page = resolved_page
      @sort = resolved_sort
      @direction = resolved_direction
      @visible_limit = @page * PER_PAGE
      @table_base_url = RecordingStudioApi.admin_logs_path(
        controller: self,
        close_url: params[:close_url],
        page: @page
      )

      if log_source_available?
        @log_records = log_scope.limit(@visible_limit).to_a
        @log_rows = log_rows
        @has_more = log_scope.count > @visible_limit
      else
        @log_records = []
        @log_rows = []
        @has_more = false
      end

      if turbo_stream_request?
        redirect_to RecordingStudioApi.admin_logs_path(
          controller: self,
          page: @page,
          sort: @sort,
          direction: @direction,
          close_url: params[:close_url]
        ), status: :see_other
        return
      end

      return unless turbo_frame_request?

      render partial: "recording_studio_api/admin_logs/content"
    end

    private

    def resolved_page
      requested_page = params[:page].to_i
      requested_page.positive? ? requested_page : 1
    end

    def log_scope
      @log_scope ||= RecordingStudioApi::ApiRequestLog.order(current_sort_column => @direction.to_sym, id: @direction.to_sym)
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

    def log_source_available?
      @log_source_available ||= RecordingStudioApi::ApiRequestLog.table_available?
    end

    def log_rows
      @log_rows ||= @log_records.map do |log|
        occurred_at = log.occurred_at || log.created_at

        {
          occurred_at_relative: relative_timestamp(occurred_at),
          occurred_at_full: full_timestamp(occurred_at),
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

    def full_timestamp(value)
      return "-" if value.blank?

      value.in_time_zone.strftime("%Y-%m-%d %H:%M:%S")
    end

    def relative_timestamp(value)
      return "-" if value.blank?

      distance = helpers.time_ago_in_words(value)
      value <= Time.current ? "#{distance} ago" : "in #{distance}"
    end

    def turbo_stream_request?
      params[:format].to_s == "turbo_stream" || request.headers["Accept"].to_s.include?("turbo-stream")
    end
  end
end