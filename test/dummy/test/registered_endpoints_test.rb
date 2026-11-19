# frozen_string_literal: true

require "test_helper"

class RegisteredEndpointsTest < ActiveSupport::TestCase
  test "dummy ping is a get named endpoint, not a recordable collection" do
    initializer = File.read(Rails.root.join("config/initializers/recording_studio_api.rb"))

    assert_includes initializer, "RecordingStudioApi.register_endpoint"
    assert_includes initializer, "http_verb: :get"
    assert_includes initializer, 'path: "ping"'
    refute_includes initializer, "RecordingStudioApi.register_action"
  end

  test "lookup resolves the dummy ping endpoint through the registered handler" do
    result = RecordingStudioApi.lookup(api: :public, endpoint: :ping)

    assert_equal false, result.sensitive
    assert_includes result.apis, :public
    assert_equal({ ok: true }, result.handler.call(nil))
  end
end
