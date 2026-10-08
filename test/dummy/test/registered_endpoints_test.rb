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
end
