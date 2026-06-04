# frozen_string_literal: true

module RecordingStudioApi
  class ApiController < ActionController::API
    API_VERSION_PATH_PATTERN = %r{/api/(?<version>v[^/]+)(?:/|$)}.freeze

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

    rescue_from ActiveRecord::RecordInvalid do |error|
      render_validation_error(error.record)
    end

    private

    def current_api_version
      @current_api_version ||= RecordingStudioApi.resolve_api_version(request_api_version)
    end

    def request_api_version
      params[:api_version].presence || request.path.match(API_VERSION_PATH_PATTERN)&.[](:version)
    end

    def render_validation_error(record)
      render_error(
        record.errors.full_messages.to_sentence,
        :unprocessable_entity,
        details: validation_error_details(record)
      )
    end

    def validation_error_details(record)
      record.errors.map do |validation_error|
        {
          attribute: validation_error.attribute,
          message: validation_error.message,
          full_message: validation_error.full_message,
          type: validation_error.type
        }
      end
    end

    def render_error(message, status, details: nil)
      payload = { error: message }
      payload[:details] = details if details.present?
      render json: payload, status: status
    end
  end
end
