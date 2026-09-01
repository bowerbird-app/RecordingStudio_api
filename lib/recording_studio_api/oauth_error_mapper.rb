# frozen_string_literal: true

module RecordingStudioApi
  class OauthErrorMapper
    SERVER_ERROR_DESCRIPTION = "The authorization server encountered an unexpected condition."

    STATUS_BY_ERROR_CODE = {
      "invalid_request" => :bad_request,
      "invalid_grant" => :bad_request,
      "invalid_scope" => :bad_request,
      "invalid_target" => :bad_request,
      "unsupported_grant_type" => :bad_request,
      "unsupported_response_type" => :bad_request,
      "unauthorized_client" => :bad_request,
      "invalid_client" => :unauthorized,
      "access_denied" => :forbidden,
      "server_error" => :internal_server_error,
      "temporarily_unavailable" => :service_unavailable
    }.freeze

    class << self
      def payload_for(error)
        return error.symbolize_keys if error.is_a?(Hash)

        server_error_payload
      end

      def server_error_payload
        {
          error: "server_error",
          error_description: SERVER_ERROR_DESCRIPTION
        }
      end

      def status_for(payload)
        code = payload.fetch(:error, "invalid_request").to_s
        STATUS_BY_ERROR_CODE.fetch(code, :bad_request)
      end
    end
  end
end