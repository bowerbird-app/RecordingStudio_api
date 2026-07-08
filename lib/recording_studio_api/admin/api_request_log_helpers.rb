# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    module ApiRequestLogHelpers
      module_function

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
    end
  end
end