# frozen_string_literal: true

module RecordingStudioApi
  class OauthController < RecordingStudioApi::ApplicationController
    include RecordingStudioApi::Concerns::ApiContext
    include RecordingStudioApi::Concerns::RateLimiting
    include RecordingStudioApi::Concerns::RequestLogging
    include RecordingStudioApi::Concerns::ApiAccessControl

    OAUTH_WWW_AUTHENTICATE = 'Basic realm="RecordingStudioApi"'

    skip_before_action :verify_authenticity_token, only: :token

    def token
      prevent_token_response_storage!

      token_params = oauth_token_request_params
      result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
        grant_type: token_params[:grant_type].to_s,
        client_id: token_params[:client_id].to_s,
        client_secret: token_params[:client_secret].to_s,
        api: current_api_key
      )

      if result.failure?
        render_oauth_error(result.error)
      else
        render json: result.value
      end
    end

    private

    # OAuth token endpoint parameters must come from the request body so
    # client secrets are not accepted via query strings (logs, Referer, proxies).
    def oauth_token_request_params
      raw = request.request_parameters
      {
        grant_type: raw["grant_type"] || raw[:grant_type],
        client_id: raw["client_id"] || raw[:client_id],
        client_secret: raw["client_secret"] || raw[:client_secret]
      }
    end

    def render_oauth_error(error)
      payload = RecordingStudioApi::OauthErrorMapper.payload_for(error)
      status = RecordingStudioApi::OauthErrorMapper.status_for(payload)
      if payload[:error].to_s == "invalid_client"
        response.set_header("WWW-Authenticate", OAUTH_WWW_AUTHENTICATE)
      end
      render json: payload, status: status
    end

    def prevent_token_response_storage!
      response.cache_control.replace(no_store: true, private: true)
      response.headers["Pragma"] = "no-cache"
      response.headers["Expires"] = "0"
    end
  end
end
