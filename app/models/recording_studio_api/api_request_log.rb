# frozen_string_literal: true

module RecordingStudioApi
  class ApiRequestLog < LogRecord
    self.table_name = "recording_studio_api_api_request_logs"

    before_validation :apply_request_log_classification, on: :create
    before_create :stamp_arrived_at_from_database_clock

    def self.write_payloads!(payloads)
      rows = Array(payloads).filter_map { |payload| ApiRequestLogClassification.attributes_for_insert(payload) }
      return if rows.empty?
      return unless table_available?

      insert_all(rows)
    end

    def api_client_name
      return if api_client_id.blank?

      RecordingStudioApi::ApiClient.where(id: api_client_id).pick(:name)
    end

    private

    def apply_request_log_classification
      classified = ApiRequestLogClassification.attributes_for_insert(attributes)
      return if classified.blank?

      self.api_key = classified.fetch("api_key")
      self.route_name = classified.fetch("route_name")
      self.latency_bucket_ms = classified.fetch("latency_bucket_ms")
    end

    def stamp_arrived_at_from_database_clock
      return if arrived_at.present?
      return unless self.class.connection.adapter_name.match?(/postg/i)

      self.arrived_at = self.class.connection.select_value("SELECT clock_timestamp()")
    end
  end
end
