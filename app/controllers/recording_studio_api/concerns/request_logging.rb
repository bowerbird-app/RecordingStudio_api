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
      PARAM_PAYLOAD_MODES = %w[filtered filtered_params].freeze

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
        return unless current_api.api_request_logging_enabled

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
          api_key: current_api_key,
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
        return {} unless log_request_params?

        unsafe = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : {}
        request_parameter_filter.filter(allowed_request_params(unsafe))
      end

      def log_request_params?
        PARAM_PAYLOAD_MODES.include?(current_api.api_request_logging_payload_mode.to_s)
      end

      def request_parameter_filter
        @request_parameter_filter ||= ActiveSupport::ParameterFilter.new(request_parameter_filter_keys)
      end

      def request_parameter_filter_keys
        configured_keys = Rails.application.config.filter_parameters if defined?(Rails) && Rails.respond_to?(:application)
        Array(configured_keys) + FILTERED_PARAM_KEYS
      end

      def allowed_request_params(params)
        allowed_keys = Array(current_api.api_request_log_allowed_param_keys).map(&:to_s)
        params.slice(*allowed_keys)
      end
    end
  end
end
