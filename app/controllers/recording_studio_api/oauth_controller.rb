# frozen_string_literal: true

module RecordingStudioApi
  class OauthController < ActionController::API
    def token
      result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
        grant_type: params[:grant_type].to_s,
        client_id: params[:client_id].to_s,
        client_secret: params[:client_secret].to_s
      )

      if result.failure?
        render_oauth_error(result.error)
      else
        render json: result.value
      end
    end

    private

    def render_oauth_error(error)
      payload = normalize_error_payload(error)
      status = payload.fetch(:error) == "invalid_client" ? :unauthorized : :unprocessable_entity
      render json: payload, status: status
    end

    def normalize_error_payload(error)
      return error.symbolize_keys if error.is_a?(Hash)

      { error: "invalid_request", error_description: error.to_s }
    end
  end
end