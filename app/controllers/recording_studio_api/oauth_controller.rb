# frozen_string_literal: true

module RecordingStudioApi
  class OauthController < RecordingStudioApi::ApplicationController
    include RecordingStudioApi::Concerns::ApiContext
    include RecordingStudioApi::Concerns::RateLimiting
    include RecordingStudioApi::Concerns::RequestLogging
    include RecordingStudioApi::Concerns::ApiAccessControl

    OAUTH_WWW_AUTHENTICATE = 'Basic realm="RecordingStudioApi"'

    skip_before_action :verify_authenticity_token, only: %i[token revoke]

    def token
      prevent_token_response_storage!

      token_params = oauth_client_credential_params
      result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
        grant_type: oauth_body_param("grant_type").to_s,
        client_id: token_params.fetch(:client_id),
        client_secret: token_params.fetch(:client_secret),
        api: current_api_key,
        params: request.request_parameters
      )

      if result.failure?
        render_oauth_error(result.error)
      else
        render json: result.value
      end
    end

    def revoke
      prevent_token_response_storage!

      token_params = oauth_client_credential_params
      result = RecordingStudioApi::Services::RevokeOauthAccessToken.call(
        token: oauth_body_param("token").to_s,
        token_type_hint: oauth_body_param("token_type_hint").to_s.presence,
        client_id: token_params.fetch(:client_id),
        client_secret: token_params.fetch(:client_secret),
        api: current_api_key
      )

      if result.failure?
        render_oauth_error(result.error)
      else
        head :ok
      end
    end

    private

    # OAuth client credentials may be supplied in the request body or via HTTP Basic.
    # Query-string credentials are never accepted.
    def oauth_client_credential_params
      body_client_id = oauth_body_param("client_id").to_s
      body_client_secret = oauth_body_param("client_secret").to_s
      basic_client_id, basic_client_secret = http_basic_client_credentials

      {
        client_id: body_client_id.presence || basic_client_id.to_s,
        client_secret: body_client_secret.presence || basic_client_secret.to_s
      }
    end

    def oauth_body_param(key)
      raw = request.request_parameters
      raw[key] || raw[key.to_sym]
    end

    def http_basic_client_credentials
      authenticate_with_http_basic do |username, password|
        return [username, password]
      end
      [nil, nil]
    end

    def render_oauth_error(error)
      payload = RecordingStudioApi::OauthErrorMapper.payload_for(error)
      status = RecordingStudioApi::OauthErrorMapper.status_for(payload)
      response.set_header("WWW-Authenticate", OAUTH_WWW_AUTHENTICATE) if payload[:error].to_s == "invalid_client"
      render json: payload, status: status
    end

    def prevent_token_response_storage!
      response.cache_control.replace(no_store: true, private: true)
      response.headers["Pragma"] = "no-cache"
      response.headers["Expires"] = "0"
    end
  end
end
