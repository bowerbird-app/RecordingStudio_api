# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "../test_helper"
require_relative "../dummy/config/environment"
require "rails/test_help"

# Load while the boot configuration still holds Moveable's extension.
# Later tests replace that configuration; the rescue stays on the class.
raise "ApiController did not load" unless RecordingStudioApi::ApiController.is_a?(Class)

class ApiControllerExtensionTest < ActionDispatch::IntegrationTest
  test "extension applied to a loaded api controller rescues the action" do
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

  test "extension applied to a second loaded api controller rescues the action" do
    assert_operator ApiExtensionBeforeController, :<, ActionController::API

    RecordingStudioApi.configuration.hooks.extend_controller(:ApiExtensionBeforeController) do
      rescue_from ApiExtensionBeforeError do |error|
        render json: { error: { code: "conflict", message: error.message } }, status: :conflict
      end
    end
    RecordingStudioApi::Engine.apply_loaded_controller_extensions

    get "/api-extension-before"

    assert_response :conflict
    body = JSON.parse(response.body)
    assert_equal "conflict", body.dig("error", "code")
    assert_equal "registered first", body.dig("error", "message")
  end

  test "autoload callback applies an extension when an api controller loads" do
    controller = Class.new(ActionController::API) do
      def self.name
        "OnLoadApiController"
      end
    end

    RecordingStudioApi.configuration.hooks.extend_controller(:OnLoadApiController) do
      rescue_from StandardError do |_error|
        # Applied only to prove the autoload callback ran.
      end
    end
    refute_includes controller.rescue_handlers.map(&:first), "StandardError"

    callback = autoload_extension_callback
    assert callback, "expected the controller autoload callback to be registered"
    callback.call(controller.name, controller, nil)

    assert_includes controller.rescue_handlers.map(&:first), "StandardError"
  end

  test "boot installs extend_controller rescues on the api controller" do
    handlers = RecordingStudioApi::ApiController.rescue_handlers.map(&:first)

    assert_includes handlers, "RecordingStudio::Moveable::Api::Conflict"
  end

  private

  def autoload_extension_callback
    Rails.autoloaders.each do |loader|
      callbacks = loader.instance_variable_get(:@on_load_callbacks)
      match = Array(callbacks && callbacks[:ANY]).find do |candidate|
        candidate.source_location&.first&.end_with?("recording_studio_api/engine.rb")
      end
      return match if match
    end
    nil
  end
end
