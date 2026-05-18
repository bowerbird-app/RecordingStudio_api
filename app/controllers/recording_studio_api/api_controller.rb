# frozen_string_literal: true

module RecordingStudioApi
  class ApiController < ActionController::API
    include RecordingStudioApi::Concerns::BearerAuthentication

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

    private

    def render_error(message, status)
      render json: { error: message }, status: status
    end
  end
end
