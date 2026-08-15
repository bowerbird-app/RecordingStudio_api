# frozen_string_literal: true

module RecordingStudioApi
  class WriteApiRequestLogsJob < ActiveJob::Base
    queue_as :recording_studio_api_logging

    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    def perform(payloads)
      rows = Array(payloads).filter_map { |payload| normalize_row(payload) }
      return if rows.empty?
      return unless ApiRequestLog.table_available?

      if rows.length == 1
        ApiRequestLog.create!(rows.first)
      else
        now = Time.current
        ApiRequestLog.insert_all(
          rows.map { |row| row.merge("created_at" => now, "updated_at" => now) }
        )
      end
    end

    private

    def normalize_row(payload)
      return if payload.blank?

      data = payload.respond_to?(:to_h) ? payload.to_h : payload
      data = data.deep_stringify_keys
      occurred_at = data["occurred_at"]
      occurred_at = Time.iso8601(occurred_at) if occurred_at.is_a?(String)

      {
        "occurred_at" => occurred_at,
        "request_id" => data["request_id"],
        "request_method" => data["request_method"],
        "request_path" => data["request_path"],
        "route_name" => data["route_name"],
        "controller_name" => data["controller_name"],
        "action_name" => data["action_name"],
        "status_code" => data["status_code"],
        "duration_ms" => data["duration_ms"],
        "rate_limited" => data["rate_limited"],
        "api_key" => data["api_key"],
        "api_client_id" => data["api_client_id"],
        "api_credential_id" => data["api_credential_id"],
        "access_recording_id" => data["access_recording_id"],
        "root_recording_id" => data["root_recording_id"],
        "remote_ip" => data["remote_ip"],
        "user_agent" => data["user_agent"],
        "error_class" => data["error_class"],
        "error_message" => data["error_message"],
        "request_params" => data["request_params"] || {}
      }
    end
  end
end
