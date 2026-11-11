# frozen_string_literal: true

require "test_helper"

class RequestPayloadTest < Minitest::Test
  Context = Struct.new(:request_params, :params, keyword_init: true)

  def test_empty_request_params_hash_does_not_fall_back_to_params
    context = Context.new(request_params: {}, params: { "title" => "x" })

    assert_equal({}, RecordingStudioApi::RequestPayload.call(context))
  end

  def test_uses_params_when_request_params_is_nil
    context = Context.new(request_params: nil, params: { "title" => "From params" })

    assert_equal({ "title" => "From params" }, RecordingStudioApi::RequestPayload.call(context))
  end

  def test_uses_request_params_when_present
    context = Context.new(request_params: { "title" => "From request" }, params: {})

    assert_equal({ "title" => "From request" }, RecordingStudioApi::RequestPayload.call(context))
  end

  def test_prefers_request_params_when_both_are_present
    context = Context.new(
      request_params: { "title" => "From request" },
      params: { "title" => "From params" }
    )

    assert_equal({ "title" => "From request" }, RecordingStudioApi::RequestPayload.call(context))
  end

  def test_uses_to_unsafe_h_when_available
    raw = Object.new
    def raw.to_unsafe_h
      { "title" => "Unsafe" }
    end

    def raw.to_h
      { "title" => "Safe" }
    end
    context = Context.new(request_params: raw, params: { "title" => "From params" })

    assert_equal({ "title" => "Unsafe" }, RecordingStudioApi::RequestPayload.call(context))
  end
end
