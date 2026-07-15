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
      initialize_date_filters
      @visible_limit = @page * PER_PAGE
      @table_base_url = RecordingStudioApi.admin_logs_path(
        controller: self,
        close_url: params[:close_url],
        page: @page,
        start_date: @logs_start_date&.iso8601,
        end_date: @logs_end_date&.iso8601
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
          close_url: params[:close_url],
          start_date: @logs_start_date&.iso8601,
          end_date: @logs_end_date&.iso8601
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
      @log_scope ||= begin
        scope = RecordingStudioApi::ApiRequestLog.order(current_sort_column => @direction.to_sym, id: @direction.to_sym)
        scope = scope.where("occurred_at >= ?", @logs_start_date.beginning_of_day) if @logs_start_date.present?
        scope = scope.where("occurred_at <= ?", @logs_end_date.end_of_day) if @logs_end_date.present?
        scope
      end
    end

    def initialize_date_filters
      @logs_start_date = parsed_date(params[:start_date])
      @logs_end_date = parsed_date(params[:end_date])

      return unless @logs_start_date.present? && @logs_end_date.present?
      return unless @logs_start_date > @logs_end_date

      @logs_start_date, @logs_end_date = @logs_end_date, @logs_start_date
    end

    def parsed_date(raw_date)
      return nil if raw_date.blank?

      Date.iso8601(raw_date.to_s)
    rescue ArgumentError
      nil
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
      @log_rows ||= begin
        records = @log_records
        client_ids = records.map(&:api_client_id).compact.uniq
        client_names = if client_ids.any?
                         RecordingStudioApi::ApiClient.where(id: client_ids).pluck(:id, :name).to_h
                       else
                         {}
                       end

        records.map do |log|
          occurred_at = log.occurred_at || log.created_at

          {
            occurred_at: occurred_at,
            method: log.request_method,
            path: log.request_path,
            client_name: client_names[log.api_client_id],
            status: log.status_code.to_s,
            rate_limited: log.rate_limited? ? "Yes" : "No",
            ip_address: log.remote_ip.to_s.presence || "-",
            duration: "#{log.duration_ms} ms",
            request_id: log.request_id.presence || "-"
          }
        end
      end
    end

    def turbo_stream_request?
      params[:format].to_s == "turbo_stream" || request.headers["Accept"].to_s.include?("turbo-stream")
    end

    def admin_logs_filter_form_params
      {
        close_url: params[:close_url],
        sort: @sort,
        direction: @direction
      }.compact
    end
    helper_method :admin_logs_filter_form_params
  end
end