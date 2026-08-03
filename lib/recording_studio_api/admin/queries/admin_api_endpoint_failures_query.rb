# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    module Queries
      class AdminApiEndpointFailuresQuery
        Row = Struct.new(
          :request_method,
          :request_path,
          :total_request_count,
          :failure_count,
          :failure_rate,
          :client_error_count,
          :server_error_count,
          :dominant_status_code,
          keyword_init: true
        )

        class << self
          def call(start_date:, end_date:, api: :public)
            new(start_date:, end_date:, api: api).call
          end
        end

        def initialize(start_date:, end_date:, api:)
          @start_date = start_date
          @end_date = end_date
          @api_key = RecordingStudioApi::Admin::ApiContext.resolve(api).name
        end

        def call
          return [] unless RecordingStudioApi::ApiRequestLog.table_available?

          rows = grouped_logs.map do |(request_method, request_path), logs|
            failure_logs = logs.select { |log| failed_status_code?(log[2]) }
            status_counts = failure_logs.each_with_object(Hash.new(0)) { |log, counts| counts[log[2]] += 1 }

            Row.new(
              request_method: request_method,
              request_path: request_path,
              total_request_count: logs.size,
              failure_count: failure_logs.size,
              failure_rate: failure_logs.size.fdiv(logs.size),
              client_error_count: failure_logs.count { |log| (400..499).cover?(log[2].to_i) },
              server_error_count: failure_logs.count { |log| (500..599).cover?(log[2].to_i) },
              dominant_status_code: status_counts.max_by { |status_code, count| [count, status_code] }&.first
            )
          end

          failures = rows.select { |row| row.failure_count.positive? }
          failures.sort_by { |row| [-row.failure_rate, -row.failure_count, -row.server_error_count, row.request_method.to_s, row.request_path.to_s] }
        end

        private

        attr_reader :start_date, :end_date, :api_key

        def grouped_logs
          RecordingStudioApi::ApiRequestLog
            .where(api_key: api_key, occurred_at: start_date.beginning_of_day..end_date.end_of_day)
            .pluck(:request_method, :request_path, :status_code)
            .group_by { |request_method, request_path, _status_code| [request_method, RecordingStudioApi::Admin::ApiRequestLogHelpers.compact_path(request_path)] }
        end

        def failed_status_code?(status_code)
          (400..599).cover?(status_code.to_i) && status_code.to_i != 429
        end
      end
    end
  end
end