# frozen_string_literal: true

module RecordingStudioApi
  class ApiController < ActionController::API
    include RecordingStudioApi::Concerns::ApiContext
    include RecordingStudioApi::Concerns::BearerAuthentication
    include RecordingStudioApi::Concerns::RateLimiting
    include RecordingStudioApi::Concerns::RequestLogging
    include RecordingStudioApi::Concerns::ApiAccessControl

    API_WWW_AUTHENTICATE = 'Bearer realm="RecordingStudioApi"'

    rescue_from RecordingStudioApi::AuthenticationError do |error|
      response.set_header("WWW-Authenticate", API_WWW_AUTHENTICATE)
      render_error(code: "authentication_failed", message: error.message, status: :unauthorized)
    end

    rescue_from RecordingStudioApi::NotFoundError, ActiveRecord::RecordNotFound do |error|
      render_error(code: "not_found", message: error.message, status: :not_found)
    end

    rescue_from RecordingStudioApi::AuthorizationError do |error|
      render_error(code: "forbidden", message: error.message, status: :forbidden)
    end

    rescue_from RecordingStudioApi::UnsupportedActionError do |error|
      render_error(code: "unsupported_action", message: error.message, status: :unprocessable_entity)
    end

    rescue_from RecordingStudioApi::InvalidActionInputError do |error|
      render_error(code: "invalid_input", message: error.message, status: :unprocessable_entity, details: error.details)
    end

    rescue_from RecordingStudioApi::InvalidPaginationTokenError do |error|
      render_error(code: "invalid_pagination_token", message: error.message, status: :unprocessable_entity)
    end

    rescue_from ActiveRecord::RecordInvalid do |error|
      render_validation_error(error.record)
    end

    private

    def render_validation_error(record)
      render_error(
        code: "validation_failed",
        message: record.errors.full_messages.to_sentence,
        status: :unprocessable_entity,
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

    def render_error(code:, message:, status:, details: nil)
      render json: api_error_payload(code: code, message: message, details: details), status: status
    end

    def api_error_payload(code:, message:, details: nil)
      error = { code: code.to_s, message: message.to_s }
      error[:details] = details if details.present?
      { error: error }
    end
  end
end
