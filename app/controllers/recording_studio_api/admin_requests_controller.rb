# frozen_string_literal: true

module RecordingStudioApi
  class AdminRequestsController < AdminController
    REQUEST_STATUS_LISTS = [
      ["Success (2xx)", "success"],
      ["Client errors (4xx)", "client_error"],
      ["Server errors (5xx)", "server_error"]
    ].freeze

    def index
      initialize_filters
      load_chart_data

      return unless turbo_frame_request?

      render partial: "recording_studio_api/admin_requests/content"
    end

    private

    def initialize_filters
      @requests_chart_start_date = parsed_date(params[:start_date]) || 29.days.ago.to_date
      @requests_chart_end_date = parsed_date(params[:end_date]) || Date.current

      if @requests_chart_start_date > @requests_chart_end_date
        @requests_chart_start_date, @requests_chart_end_date = @requests_chart_end_date, @requests_chart_start_date
      end

      @requests_chart_status_lists = REQUEST_STATUS_LISTS
      @requests_chart_status = normalized_status
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
      date_window = @requests_chart_start_date..@requests_chart_end_date
      @requests_chart_categories = date_window.map { |day| day.strftime("%b %-d") }

      unless RecordingStudioApi::ApiRequestLog.table_available?
        @requests_chart_series = Array.new(@requests_chart_categories.length, 0)
        return
      end

      counts_by_date = filtered_requests_scope.group("DATE(occurred_at)").count
      @requests_chart_series = date_window.map do |day|
        counts_by_date.fetch(day, counts_by_date.fetch(day.to_s, 0))
      end
    end

    def filtered_requests_scope
      scope = RecordingStudioApi::ApiRequestLog.where(
        occurred_at: @requests_chart_start_date.beginning_of_day..@requests_chart_end_date.end_of_day
      )

      admin_controller_scope = scope.where("controller_name LIKE ?", "recording_studio_api/admin_%")
      admin_path_scope = scope.where("request_path LIKE ? OR request_path LIKE ?", "/admin/api%", "/recording_studio_api/admin_api%")
      scope = admin_controller_scope.or(admin_path_scope)

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

    def admin_requests_filter_form_params
      page_nav_close_param
    end
    helper_method :admin_requests_filter_form_params
  end
end
