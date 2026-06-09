# frozen_string_literal: true

module RecordingStudioApi
  module Concerns
    module RequestLogging
      extend ActiveSupport::Concern

      FILTERED_PARAM_KEYS = %w[
        access_token
        authorization
        bearer
        client_secret
        password
        refresh_token
        token
      ].freeze

      class << self
        attr_accessor :writer
      end

      included do
        around_action :log_api_request
      end

      private

      def log_api_request
        started_at = Time.current
        monotonic_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raised_error = nil

        yield
      rescue StandardError => error
        raised_error = error
        raise
      ensure
        write_request_log(started_at, monotonic_start, raised_error)
      end

      def write_request_log(started_at, monotonic_start, raised_error)
        return unless RecordingStudioApi.configuration.api_request_logging_enabled

        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - monotonic_start) * 1000).round
        payload = {
          occurred_at: started_at,
          request_id: request.request_id,
          request_method: request.request_method,
          request_path: request.path,
          route_name: request.path_parameters[:controller].to_s,
          controller_name: controller_path,
          action_name: action_name,
          status_code: response&.status || 500,
          duration_ms: duration_ms,
          rate_limited: !!@rate_limited_request,
          api_client_id: safe_id_for(:current_api_client),
          api_credential_id: safe_id_for(:current_api_credential),
          access_recording_id: safe_id_for(:current_access_recording),
          root_recording_id: safe_id_for(:current_root_recording),
          remote_ip: request.remote_ip,
          user_agent: request.user_agent.to_s.first(512),
          error_class: raised_error&.class&.name,
          error_message: raised_error&.message&.to_s&.first(1000),
          request_params: filtered_request_params
        }

        if RequestLogging.writer.respond_to?(:call)
          RequestLogging.writer.call(payload)
        else
          RecordingStudioApi::ApiRequestLog.create!(payload)
        end
      rescue StandardError => error
        Rails.logger.warn("[RecordingStudioApi] api request log write failed: #{error.class}: #{error.message}")
      end

      def safe_id_for(method_name)
        return unless respond_to?(method_name, true)

        value = public_send(method_name)
        value&.id
      rescue StandardError
        nil
      end

      def filtered_request_params
        unsafe = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : {}

        unsafe.each_with_object({}) do |(key, value), filtered|
          key_name = key.to_s
          filtered[key_name] = FILTERED_PARAM_KEYS.include?(key_name) ? "[FILTERED]" : value
        end
      end
    end
  end
end
