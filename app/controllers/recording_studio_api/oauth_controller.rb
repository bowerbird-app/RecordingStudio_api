# frozen_string_literal: true

module RecordingStudioApi
  class OauthController < RecordingStudioApi::ApplicationController
    include RecordingStudioApi::Concerns::RateLimiting
    include RecordingStudioApi::Concerns::RequestLogging

    skip_before_action :verify_authenticity_token, only: %i[token revoke]

    def token
      grant_type = params[:grant_type].to_s
      result = oauth_token_result_for(grant_type)

      if result.failure?
        render_oauth_error(result.error)
      else
        render json: result.value
      end
    end

    def revoke
      result = if params[:oauth_grant_session_id].present?
                 RecordingStudioApi::Services::RevokeOauthGrantSession.call(
                   oauth_grant_session_id: params[:oauth_grant_session_id].to_s,
                   authorization_header: request.headers["Authorization"]
                 )
               else
                 RecordingStudioApi::Services::RevokeOauthToken.call(
                   client_id: params[:client_id].to_s,
                   token: params[:token].to_s,
                   token_type_hint: params[:token_type_hint].presence
                 )
               end

      if result.failure?
        render_oauth_error(result.error)
      else
        head :ok
      end
    end

    private

    def render_oauth_error(error)
      payload = RecordingStudioApi::OauthErrorMapper.payload_for(error)
      status = RecordingStudioApi::OauthErrorMapper.status_for(payload)
      render json: payload, status: status
    end

    def oauth_token_result_for(grant_type)
      case grant_type
      when "authorization_code"
        RecordingStudioApi::Services::ExchangeOauthAuthorizationCode.call(
          grant_type: grant_type,
          client_id: params[:client_id].to_s,
          code: params[:code].to_s,
          redirect_uri: params[:redirect_uri].to_s,
          code_verifier: params[:code_verifier].to_s
        )
      when "refresh_token"
        RecordingStudioApi::Services::RefreshOauthAccessToken.call(
          grant_type: grant_type,
          client_id: params[:client_id].to_s,
          refresh_token: params[:refresh_token].to_s
        )
      else
        RecordingStudioApi::Services::IssueOauthAccessToken.call(
          grant_type: grant_type,
          client_id: params[:client_id].to_s,
          client_secret: params[:client_secret].to_s
        )
      end
    end

  end
end