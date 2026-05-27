# frozen_string_literal: true

module RecordingStudioApi
  class ApiController < ActionController::API
    include RecordingStudioApi::Concerns::BearerAuthentication
    include RecordingStudioApi::Concerns::RateLimiting
    include RecordingStudioApi::Concerns::RequestLogging

    rescue_from RecordingStudioApi::AuthenticationError do |error|
      render_error(error.message, :unauthorized)
    end

    rescue_from RecordingStudioApi::NotFoundError, ActiveRecord::RecordNotFound do |error|
      render_error(error.message, :not_found)
    end

    rescue_from RecordingStudioApi::AuthorizationError do |error|
      render_error(error.message, :forbidden)
    end

    rescue_from RecordingStudioApi::UnsupportedActionError do |error|
      render_error(error.message, :unprocessable_entity)
    end

    rescue_from RecordingStudioApi::InvalidActionInputError do |error|
      render_error(error.message, :unprocessable_entity, details: error.details)
    end

    rescue_from RecordingStudioApi::InvalidPaginationTokenError do |error|
      render_error(error.message, :unprocessable_entity)
    end

    private

    def authorize_api_read!
      return if api_access_policy.can_read?

      raise RecordingStudioApi::AuthorizationError, "API client does not have read access"
    end

    def authorize_api_write!
      return if api_access_policy.can_write?

      raise RecordingStudioApi::AuthorizationError, "API client does not have write access"
    end

    def authorize_api_admin!
      return if api_access_policy.can_admin?

      raise RecordingStudioApi::AuthorizationError, "API client does not have admin access"
    end

    def render_error(message, status, details: nil)
      payload = { error: message }
      payload[:details] = details if details.present?
      render json: payload, status: status
    end

    def api_access_policy
      @api_access_policy ||= RecordingStudioApi::AccessPolicy.new(access_recording: current_access_recording)
    end
  end
end
