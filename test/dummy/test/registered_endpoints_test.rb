# frozen_string_literal: true

require "test_helper"

class RegisteredEndpointsTest < ActionDispatch::IntegrationTest
  test "dummy ping is a get named endpoint, not a recordable collection" do
    initializer = File.read(Rails.root.join("config/initializers/recording_studio_api.rb"))

    assert_includes initializer, "RecordingStudioApi.register_endpoint"
    assert_includes initializer, "http_verb: :get"
    assert_includes initializer, 'path: "ping"'

    get "/recording_studio_api/api/v1/ping"

    assert_response :unauthorized
    assert_equal "authentication_failed", JSON.parse(response.body).dig("error", "code")
  end
end
