# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "../test_helper"
require_relative "../dummy/config/environment"
require "rails/test_help"

# Load while the boot configuration still holds Moveable's extension.
# Later tests replace that configuration; the rescue stays on the class.
raise "ApiController did not load" unless RecordingStudioApi::ApiController.is_a?(Class)

class ApiControllerExtensionTest < ActionDispatch::IntegrationTest
  test "ApiExtensionProbeController rescues the action after extensions are applied" do
    assert_operator ApiExtensionProbeController, :<, ActionController::API

    RecordingStudioApi.configuration.hooks.extend_controller(:ApiExtensionProbeController) do
      rescue_from ApiExtensionProbeError do |error|
        render json: { error: { code: "conflict", message: error.message } }, status: :conflict
      end
    end
    RecordingStudioApi::Engine.apply_loaded_controller_extensions

    get "/api-extension-probe"

    assert_response :conflict
    body = JSON.parse(response.body)
    assert_equal "conflict", body.dig("error", "code")
    assert_equal "probe failed", body.dig("error", "message")
  end

  test "ApiExtensionLoadedController rescues the action after extensions are applied" do
    assert_operator ApiExtensionLoadedController, :<, ActionController::API

    RecordingStudioApi.configuration.hooks.extend_controller(:ApiExtensionLoadedController) do
      rescue_from ApiExtensionLoadedError do |error|
        render json: { error: { code: "conflict", message: error.message } }, status: :conflict
      end
    end
    RecordingStudioApi::Engine.apply_loaded_controller_extensions

    get "/api-extension-loaded"

    assert_response :conflict
    body = JSON.parse(response.body)
    assert_equal "conflict", body.dig("error", "code")
    assert_equal "loaded controller", body.dig("error", "message")
  end

  test "an unloaded api controller picks up the extension when it autoloads" do
    assert Object.autoload?(:ApiExtensionAutoloadController)

    RecordingStudioApi.configuration.hooks.extend_controller(:ApiExtensionAutoloadController) do
      rescue_from ApiExtensionAutoloadError do |error|
        render json: { error: { code: "conflict", message: error.message } }, status: :conflict
      end
    end

    get "/api-extension-autoload"

    assert_response :conflict
    body = JSON.parse(response.body)
    assert_equal "conflict", body.dig("error", "code")
    assert_equal "autoloaded controller", body.dig("error", "message")
    assert_includes ApiExtensionAutoloadController.rescue_handlers.map(&:first), "ApiExtensionAutoloadError"
  end

  test "boot installs extend_controller rescues on the api controller" do
    handlers = RecordingStudioApi::ApiController.rescue_handlers.map(&:first)

    assert_includes handlers, "RecordingStudio::Moveable::Api::Conflict"
  end
end
