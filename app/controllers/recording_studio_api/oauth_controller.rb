# frozen_string_literal: true

module RecordingStudioApi
  class OauthController < RecordingStudioApi::ApplicationController
    include RecordingStudioApi::Concerns::ApiContext
    include RecordingStudioApi::Concerns::RateLimiting
    include RecordingStudioApi::Concerns::RequestLogging
    include RecordingStudioApi::Concerns::ApiAccessControl

    skip_before_action :verify_authenticity_token, only: :token

    def token
      prevent_token_response_storage!

      result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
        grant_type: params[:grant_type].to_s,
        client_id: params[:client_id].to_s,
        client_secret: params[:client_secret].to_s,
        api: current_api_key
      )

      if result.failure?
        render_oauth_error(result.error)
      else
        render json: result.value
      end
    end

    private

    def render_oauth_error(error)
      payload = RecordingStudioApi::OauthErrorMapper.payload_for(error)
      status = RecordingStudioApi::OauthErrorMapper.status_for(payload)
      render json: payload, status: status
    end

    def prevent_token_response_storage!
      response.cache_control.replace(no_store: true, private: true)
      response.headers["Pragma"] = "no-cache"
      response.headers["Expires"] = "0"
    end

  end
end
