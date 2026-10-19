# frozen_string_literal: true

module RecordingStudioApi
  module ApiRequestLogClassification
    BUCKETS_MS = [25, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000, 30_000].freeze
    DEFAULT_API_KEY = "public"
    DEFAULT_ROUTE_NAME = "unknown"

    module_function

    def attributes_for_insert(payload)
      return if payload.blank?

      data = stringify(payload)
      duration_ms = data["duration_ms"]

      {
        "occurred_at" => parse_time(data["occurred_at"]),
        "request_id" => data["request_id"],
        "request_method" => data["request_method"],
        "request_path" => data["request_path"],
        "route_name" => normalize_route_name(data["route_name"]),
        "controller_name" => data["controller_name"],
        "action_name" => data["action_name"],
        "status_code" => data["status_code"],
        "duration_ms" => duration_ms,
        "rate_limited" => data["rate_limited"],
        "api_key" => normalize_api_key(data["api_key"]),
        "api_client_id" => data["api_client_id"],
        "api_credential_id" => data["api_credential_id"],
        "access_recording_id" => data["access_recording_id"],
        "root_recording_id" => data["root_recording_id"],
        "remote_ip" => data["remote_ip"],
        "user_agent" => data["user_agent"],
        "error_class" => data["error_class"],
        "error_message" => data["error_message"],
        "request_params" => data["request_params"].presence || {},
        "latency_bucket_ms" => bucket_ms(duration_ms)
      }
    end

    def normalize_api_key(value)
      stripped = value.to_s.strip
      stripped.empty? ? DEFAULT_API_KEY : stripped
    end

    def normalize_route_name(value)
      stripped = value.to_s.strip
      stripped.empty? ? DEFAULT_ROUTE_NAME : stripped
    end

    def bucket_ms(duration_ms)
      return if duration_ms.nil?

      duration = Integer(duration_ms)
      BUCKETS_MS.each_with_index do |upper_bound, index|
        lower = index.zero? ? 0 : BUCKETS_MS[index - 1] + 1
        return upper_bound if index == BUCKETS_MS.length - 1 && duration >= lower
        return upper_bound if duration.between?(lower, upper_bound)
      end
    end

    def bucket_case_sql(column = "duration_ms")
      clauses = BUCKETS_MS.map.with_index do |upper_bound, index|
        lower = index.zero? ? 0 : BUCKETS_MS[index - 1] + 1
        if index == BUCKETS_MS.length - 1
          "WHEN #{column} >= #{lower} THEN #{upper_bound}"
        else
          "WHEN #{column} BETWEEN #{lower} AND #{upper_bound} THEN #{upper_bound}"
        end
      end
      clauses.join(" ")
    end

    def stringify(payload)
      data = payload.respond_to?(:to_h) ? payload.to_h : payload
      data.respond_to?(:deep_stringify_keys) ? data.deep_stringify_keys : data.transform_keys(&:to_s)
    end
    private_class_method :stringify

    def parse_time(value)
      return value if value.acts_like?(:time)
      return Time.iso8601(value) if value.is_a?(String) && value.present?

      value
    end
    private_class_method :parse_time
  end
end
