# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "../test_helper"
require_relative "../dummy/config/environment"
require "rails/test_help"

class ApiControllerExtensionTest < ActionDispatch::IntegrationTest
  test "extension registered after an api controller loaded rescues the action" do
    assert_operator ApiExtensionProbeController, :<, ActionController::API

    RecordingStudioApi.configuration.hooks.extend_controller(:ApiExtensionProbeController) do
      rescue_from ApiExtensionProbeError do |error|
        render json: { error: { code: "conflict", message: error.message } }, status: :conflict
      end
    end

    get "/api-extension-probe"

    assert_response :conflict
    body = JSON.parse(response.body)
    assert_equal "conflict", body.dig("error", "code")
    assert_equal "probe failed", body.dig("error", "message")
  end

  test "extension registered before an api controller loads rescues the action" do
    RecordingStudioApi.configuration.hooks.extend_controller(:ApiExtensionBeforeController) do
      rescue_from ApiExtensionBeforeError do |error|
        render json: { error: { code: "conflict", message: error.message } }, status: :conflict
      end
    end

    get "/api-extension-before"

    assert_response :conflict
    body = JSON.parse(response.body)
    assert_equal "conflict", body.dig("error", "code")
    assert_equal "registered first", body.dig("error", "message")
  end

  test "boot installs extend_controller rescues on the api controller" do
    handlers = RecordingStudioApi::ApiController.rescue_handlers.map(&:first)

    assert_includes handlers, "RecordingStudio::Moveable::Api::Conflict"
  end
end
