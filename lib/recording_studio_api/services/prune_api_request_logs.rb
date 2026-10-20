# frozen_string_literal: true

module RecordingStudioApi
  module Services
    class PruneApiRequestLogs
      class << self
        def call(before: default_before)
          return GuardedApiRequestLogRetention.call(before: before) if LogsRegistration.summaries_enabled?
          return 0 unless ApiRequestLog.table_available?

          ApiRequestLog.where("occurred_at < ?", before).delete_all
        end

        private

        def default_before
          retention_days = RecordingStudioApi::ApiRuntimePolicy.for(:public).api_request_log_retention_days
          return Time.at(0) if retention_days.nil?

          Time.current - retention_days.to_i.days
        end
      end
    end
  end
end