# frozen_string_literal: true

module RecordingStudioApi
  class AdminLogsController < AdminController
    PER_PAGE = 25

    def index
      @page = resolved_page
      @visible_limit = @page * PER_PAGE

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
        redirect_to RecordingStudioApi.admin_logs_path(controller: self, page: @page), status: :see_other
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
      @log_scope ||= RecordingStudioApi::ApiRequestLog.order(occurred_at: :desc, id: :desc)
    end

    def log_source_available?
      @log_source_available ||= RecordingStudioApi::ApiRequestLog.table_available?
    end

    def log_rows
      @log_rows ||= @log_records.map do |log|
        {
          occurred_at: timestamp(log.occurred_at || log.created_at),
          method: log.request_method,
          path: log.request_path,
          status: log.status_code.to_s,
          duration: "#{log.duration_ms} ms",
          request_id: log.request_id.presence || "-"
        }
      end
    end

    def timestamp(value)
      return "-" if value.blank?

      value.in_time_zone.strftime("%Y-%m-%d %H:%M:%S")
    end

    def turbo_stream_request?
      params[:format].to_s == "turbo_stream" || request.headers["Accept"].to_s.include?("turbo-stream")
    end
  end
end