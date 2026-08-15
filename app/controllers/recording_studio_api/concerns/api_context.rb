# frozen_string_literal: true

module RecordingStudioApi
  module Concerns
    module ApiContext
      extend ActiveSupport::Concern

      private

      def current_api_key
        current_api.name
      end

      def current_api
        @current_api ||= RecordingStudioApi.configuration.fetch_api(request.path_parameters[:api_key].presence || :public)
      rescue RecordingStudioApi::ConfigurationError
        raise RecordingStudioApi::NotFoundError, "Unknown API"
      end

      def current_runtime_policy
        @current_runtime_policy ||= RecordingStudioApi::ApiRuntimePolicy.for(current_api_key)
      end

      def current_api_version
        @current_api_version ||= begin
          requested_version = request.path_parameters[:api_version].presence
          raise RecordingStudioApi::NotFoundError, "Unsupported API version" unless RecordingStudioApi.supported_api_version?(requested_version, api: current_api_key)

          RecordingStudioApi.resolve_api_version(requested_version, api: current_api_key)
        end
      end
    end
  end
end