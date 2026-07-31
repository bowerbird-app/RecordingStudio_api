# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    module ApiRequestLogHelpers
      module_function

      def compact_path(path)
        normalized_path = path.to_s
                              .sub(%r{\A/recording_studio_api/api/v\d+(?=/|\z)}, "")
                              .sub(%r{\A/api/v\d+(?=/|\z)}, "")
                              .sub(%r{\A/recording_studio_api(?=/|\z)}, "")

        normalized_path = "/" if normalized_path.blank?
        normalized_path.gsub(
          %r{/(?:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|\d+)(?=/|\z)}i,
          "/:id"
        )
      end

      def compact_path_tooltip(view_context, path)
        view_context.render FlatPack::Tooltip::Component.new(text: path) do
          view_context.content_tag(
            :span,
            compact_path(path),
            class: "underline decoration-dotted underline-offset-2"
          )
        end
      end

      def sanitize_like(value)
        ActiveRecord::Base.sanitize_sql_like(value.to_s)
      end

      def status_badge_options(value)
        status_code = value.to_i
        {
          text: value.to_s,
          size: :sm,
          style: case status_code
                 when 200..299 then :success
                 when 300..399 then :info
                 when 400..499 then :warning
                 when 500..599 then :danger
                 else :default
                 end
        }
      end

      def rate_limited_badge_options(value)
        rate_limited = ActiveModel::Type::Boolean.new.cast(value)
        {
          text: rate_limited ? "Yes" : "No",
          size: :sm,
          style: rate_limited ? :danger : :default
        }
      end

      def metric_rows(start_date:, end_date:, status_class: nil, rate_limited: nil, api: :public)
        RecordingStudioApi::Admin::Queries::ApiMetricsQuery.call(
          start_date: start_date,
          end_date: end_date,
          status_class: status_class,
          rate_limited: rate_limited,
          api: api
        )
      end

      def metric_total(start_date:, end_date:, status_class: nil, rate_limited: nil, api: :public)
        metric_rows(start_date:, end_date:, status_class:, rate_limited:, api: api).sum(&:request_count)
      end

      def daily_metric_counts(start_date:, end_date:, status_class: nil, rate_limited: nil, api: :public)
        counts = (start_date..end_date).index_with(0)
        metric_rows(start_date:, end_date:, status_class:, rate_limited:, api: api).each do |row|
          counts[row.metric_date] += row.request_count if counts.key?(row.metric_date)
        end
        counts
      end
    end
  end
end