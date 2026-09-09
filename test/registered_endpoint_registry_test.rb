# frozen_string_literal: true

require "test_helper"

class RegisteredEndpointRegistryTest < Minitest::Test
  def setup
    @registry = RecordingStudioApi::RegisteredEndpointRegistry.new
  end

  def test_register_stores_an_endpoint_without_a_recordable
    @registry.register(
      :ping,
      http_verb: :get,
      path: "ping",
      handler: ->(_context) { { ok: true } }
    )

    registration = @registry.fetch(:ping)

    assert_equal "ping", registration.name
    assert_equal :get, registration.http_verb
    assert_equal "ping", registration.path
    assert_equal({ ok: true }, registration.handler.call(nil))
  end

  def test_match_captures_path_tokens
    @registry.register(
      :describe_widget,
      http_verb: :get,
      path: "widgets/:key",
      handler: ->(_context) { :ok }
    )

    match = @registry.match(path: "widgets/button", http_verb: :get)

    assert_equal "describe_widget", match.endpoint.name
    assert_equal({ key: "button" }, match.captures)
  end

  def test_match_path_ignores_http_verb
    @registry.register(
      :echo,
      http_verb: :post,
      path: "echo",
      handler: ->(_context) { :ok }
    )

    match = @registry.match_path("echo")

    assert_equal "echo", match.endpoint.name
    assert_nil @registry.match(path: "echo", http_verb: :get)
  end

  def test_rejects_duplicate_names
    @registry.register(:ping, http_verb: :get, path: "ping", handler: ->(_context) { :ok })

    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      @registry.register(:ping, http_verb: :post, path: "pong", handler: ->(_context) { :ok })
    end

    assert_equal "API endpoint ping is already registered", error.message
  end

  def test_rejects_duplicate_verb_and_path
    @registry.register(:ping, http_verb: :get, path: "status", handler: ->(_context) { :ok })

    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      @registry.register(:status, http_verb: :get, path: "status", handler: ->(_context) { :ok })
    end

    assert_equal "API endpoint path GET status is already registered", error.message
  end

  def test_rejects_missing_handler
    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      @registry.register(:ping, http_verb: :get, path: "ping", handler: nil)
    end

    assert_equal "Handler is required for ping", error.message
  end

  def test_rejects_unsafe_paths
    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      @registry.register(:bad, http_verb: :get, path: "../secret", handler: ->(_context) { :ok })
    end

    assert_equal "API endpoint path must not contain .. for bad", error.message
  end

  def test_rejects_blank_paths_and_unsupported_verbs
    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      @registry.register(:blank, http_verb: :get, path: "/", handler: ->(_context) { :ok })
    end
    assert_equal "API endpoint path is required for blank", error.message

    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      @registry.register(:remote, http_verb: :get, path: "https://example.com/x", handler: ->(_context) { :ok })
    end
    assert_equal "API endpoint path must be relative for remote", error.message

    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      @registry.register(:bad_verb, http_verb: :head, path: "status", handler: ->(_context) { :ok })
    end
    assert_equal "Unsupported HTTP verb head for bad_verb", error.message
  end

  def test_rejects_invalid_path_segments
    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      @registry.register(:bad, http_verb: :get, path: "not valid", handler: ->(_context) { :ok })
    end

    assert_includes error.message, "Invalid API endpoint path segment"
  end

  def test_normalizes_a_leading_slash_and_exposes_openapi_path_parameters
    @registry.register(
      :describe_widget,
      http_verb: :get,
      path: "/widgets/:key",
      handler: ->(_context) { :ok },
      openapi: { tags: ["Widgets"] },
      input_contract: {
        fields: { key: { type: :string, required: true } }
      }
    )

    registration = @registry[:describe_widget]
    assert_equal "widgets/:key", registration.path
    assert_equal ["Widgets"], registration.openapi_tags
    assert_equal(
      [{ name: "key", in: "path", required: true, schema: { type: "string" } }],
      registration.openapi_path_parameters
    )
    assert_nil @registry[:missing]
    assert_raises(KeyError) { @registry.fetch(:missing) }
    @registry.validate!
    assert_equal "describe_widget", @registry.to_h.fetch("describe_widget").fetch(:name)
  end
end
