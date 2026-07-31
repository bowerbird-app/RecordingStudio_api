# frozen_string_literal: true

module RecordingStudioApi
  class AdminErrorsController < AdminController
    NO_EXCEPTION_VALUE = "__none__"
    GROUP_BY_OPTIONS = [
      %w[Day day],
      %w[Week week],
      %w[Month month],
      %w[Year year]
    ].freeze

    def index
      initialize_filters
      load_chart_data

      return unless turbo_frame_request?

      render partial: "recording_studio_api/admin_errors/content"
    end

    private

    def initialize_filters
      @errors_chart_start_date = parsed_date(params[:start_date]) || 29.days.ago.to_date
      @errors_chart_end_date = parsed_date(params[:end_date]) || Date.current

      @errors_chart_start_date, @errors_chart_end_date = @errors_chart_end_date, @errors_chart_start_date if @errors_chart_start_date > @errors_chart_end_date

      @errors_chart_error_type_options = error_type_options
      @errors_chart_error_type = normalized_error_type
      @errors_chart_group_by_options = GROUP_BY_OPTIONS
      @errors_chart_group_by = normalized_group_by
    end

    def parsed_date(raw_date)
      return nil if raw_date.blank?

      Date.iso8601(raw_date.to_s)
    rescue ArgumentError
      nil
    end

    def error_type_options
      return [] unless RecordingStudioApi::ApiRequestLog.table_available?

      options = [["No exception captured", NO_EXCEPTION_VALUE]]
      classes = errors_base_scope.where.not(error_class: [nil, ""]).distinct.order(:error_class).pluck(:error_class)
      options + classes.map { |error_class| [error_class, error_class] }
    end

    def normalized_error_type
      requested_type = params[:error_type].to_s
      return nil if requested_type.blank?

      allowed_types = @errors_chart_error_type_options.map { |(_label, value)| value }
      allowed_types.include?(requested_type) ? requested_type : nil
    end

    def load_chart_data
      bucket_starts = chart_bucket_starts
      @errors_chart_categories = bucket_starts.map { |bucket_start| chart_bucket_label(bucket_start) }

      unless RecordingStudioApi::ApiRequestLog.table_available?
        @errors_chart_series = Array.new(@errors_chart_categories.length, 0)
        return
      end

      counts_by_bucket = bucket_starts.index_with(0)
      filtered_errors_scope.pluck(:occurred_at).each do |occurred_at|
        bucket_start = chart_bucket_start_for(occurred_at)
        counts_by_bucket[bucket_start] += 1 if counts_by_bucket.key?(bucket_start)
      end

      @errors_chart_series = bucket_starts.map do |bucket_start|
        counts_by_bucket.fetch(bucket_start, 0)
      end
    end

    def normalized_group_by
      requested_group_by = params[:group_by].to_s
      allowed_group_bys = GROUP_BY_OPTIONS.map { |(_label, value)| value }
      allowed_group_bys.include?(requested_group_by) ? requested_group_by : "day"
    end

    def filtered_errors_scope
      scope = errors_base_scope

      case @errors_chart_error_type
      when NO_EXCEPTION_VALUE
        scope.where(error_class: [nil, ""])
      when nil
        scope
      else
        scope.where(error_class: @errors_chart_error_type)
      end
    end

    def errors_base_scope
      return @errors_base_scope if defined?(@errors_base_scope)

      scope = RecordingStudioApi::ApiRequestLog.where(
        api_key: @current_admin_api.name,
        occurred_at: @errors_chart_start_date.beginning_of_day..@errors_chart_end_date.end_of_day,
        status_code: 400..599
      )

      admin_controller_scope = scope.where("controller_name LIKE ?", "recording_studio_api/admin_%")
      admin_path_scope = scope.where("request_path LIKE ? OR request_path LIKE ?", "/admin/api%", "/recording_studio_api/admin_api%")
      admin_scope = admin_controller_scope.or(admin_path_scope)

      # Prefer explicit admin error logs, but fall back to all API errors when
      # host apps only record non-admin API endpoints.
      @errors_base_scope = admin_scope.exists? ? admin_scope : scope
    end

    def admin_errors_filter_form_params
      page_nav_close_param
    end
    helper_method :admin_errors_filter_form_params

    def chart_bucket_starts
      case @errors_chart_group_by
      when "week"
        build_time_buckets(
          @errors_chart_start_date.beginning_of_week.to_date,
          @errors_chart_end_date.beginning_of_week.to_date
        ) { |date| date + 1.week }
      when "month"
        build_time_buckets(
          @errors_chart_start_date.beginning_of_month,
          @errors_chart_end_date.beginning_of_month
        ) { |date| date.next_month.beginning_of_month }
      when "year"
        build_time_buckets(
          @errors_chart_start_date.beginning_of_year,
          @errors_chart_end_date.beginning_of_year
        ) { |date| date.next_year.beginning_of_year }
      else
        build_time_buckets(@errors_chart_start_date, @errors_chart_end_date) { |date| date + 1.day }
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
      occurred_date = occurred_at.to_date

      case @errors_chart_group_by
      when "week"
        occurred_date.beginning_of_week.to_date
      when "month"
        occurred_date.beginning_of_month
      when "year"
        occurred_date.beginning_of_year
      else
        occurred_date
      end
    end

    def chart_bucket_label(bucket_start)
      case @errors_chart_group_by
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
