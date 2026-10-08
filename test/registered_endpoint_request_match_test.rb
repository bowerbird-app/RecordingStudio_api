# frozen_string_literal: true

require_relative "support/api_dummy_helpers"

class RegisteredEndpointRequestMatchTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    RecordingStudioApi.register_endpoint(
      :list_people,
      http_verb: :get,
      path: "people",
      handler: ->(_context) { :list }
    )
    RecordingStudioApi.register_endpoint(
      :create_person,
      http_verb: :post,
      path: "people",
      handler: ->(_context) { :create }
    )
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
  end

  test "request match uses path and http verb" do
    get_match = RecordingStudioApi.registered_endpoint_request_match(fake_request(path: "people", verb: :get))
    post_match = RecordingStudioApi.registered_endpoint_request_match(fake_request(path: "people", verb: :post))

    assert_equal "list_people", get_match.endpoint.name
    assert_equal "create_person", post_match.endpoint.name
    assert_nil RecordingStudioApi.registered_endpoint_request_match(fake_request(path: "people", verb: :delete))
  end

  test "path match stays verb-blind for routing and allowed verbs" do
    request = fake_request(path: "people", verb: :delete)

    assert_equal "list_people", RecordingStudioApi.registered_endpoint_path_match(request).endpoint.name
    assert_equal %i[get post], RecordingStudioApi.registered_endpoint_http_verbs(request)
  end

  test "recordable collection names are not treated as registered endpoints" do
    request = fake_request(path: "pages", verb: :get)

    assert_nil RecordingStudioApi.registered_endpoint_request_match(request)
    assert_nil RecordingStudioApi.registered_endpoint_path_match(request)
  end

  private

  def fake_request(path:, verb:, api_key: "public")
    path_parameters = { api_key: api_key, standalone_path: path.split("/") }
    request = Object.new
    request.define_singleton_method(:path_parameters) { path_parameters }
    request.define_singleton_method(:request_method_symbol) { verb }
    request
  end
end
