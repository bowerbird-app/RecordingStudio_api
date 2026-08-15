# frozen_string_literal: true

module RecordingStudioApi
  module Concerns
    module ApiAccessControl
      extend ActiveSupport::Concern

      included do
        prepend_before_action :ensure_api_access_enabled!
      end

      private

      def ensure_api_access_enabled!
        return if RecordingStudioApi::ApiSetting.api_access_enabled?(api: current_api_key)

        if respond_to?(:api_error_payload, true)
          render json: api_error_payload(
            code: "api_access_disabled",
            message: "API access is temporarily disabled"
          ), status: :service_unavailable
        else
          render json: {
            error: "api_access_disabled",
            error_description: "API access is temporarily disabled"
          }, status: :service_unavailable
        end
      end
    end
  end
end