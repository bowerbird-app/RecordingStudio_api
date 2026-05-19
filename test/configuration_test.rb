# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  def setup
    @configuration = RecordingStudioApi::Configuration.new
  end

  def test_merge_updates_known_attributes
    @configuration.merge!(timeout: 9, enable_feature_x: true)

    assert_equal 9, @configuration.timeout
    assert_equal true, @configuration.enable_feature_x
  end

  def test_merge_ignores_unknown_keys
    @configuration[:unknown_key] = "ignored"
    @configuration[:timeout] = 7

    assert_not_respond_to @configuration, :unknown_key
    assert_equal 7, @configuration.timeout
  end

  def test_merge_with_non_enumerable_is_noop
    original = @configuration.to_h

    @configuration.merge!(nil)

    assert_equal original[:timeout], @configuration.timeout
    assert_equal original[:enable_feature_x], @configuration.enable_feature_x
  end

  def test_initialize_uses_defaults
    configuration = RecordingStudioApi::Configuration.new

    assert_equal false, configuration.enable_feature_x
    assert_equal 5, configuration.timeout
    assert_nil configuration.openapi_title
    assert_instance_of RecordingStudioApi::Hooks, configuration.hooks
  end

  def test_merge_updates_openapi_title
    @configuration.merge!(openapi_title: "My API")

    assert_equal "My API", @configuration.openapi_title
  end

  def test_merge_accepts_string_keys
    @configuration["timeout"] = 12

    assert_equal 12, @configuration.timeout
  end

  def test_to_h_reports_registered_hook_counts
    @configuration.hooks.before_initialize { nil }
    @configuration.hooks.before_initialize { nil }
    @configuration.hooks.after_service { nil }

    result = @configuration.to_h

    assert_equal 2, result.fetch(:hooks_registered).fetch(:before_initialize)
    assert_equal 1, result.fetch(:hooks_registered).fetch(:after_service)
  end

  def test_register_capability_action_tracks_registry_entries
    @configuration.action_registry.register(
      :echo,
      capability: :echoable,
      handler: ->(_context) { :ok }
    )

    assert_equal :echoable, @configuration.to_h.fetch(:action_registrations).fetch("echo").fetch(:action)
  end

  def test_register_recordable_type_api_tracks_registry_entries
    @configuration.recordable_registry.register(
      "Page",
      serializer: ->(recordable) { { title: recordable.title } },
      openapi: { details_schema: { type: "object" } }
    )

    registration = @configuration.to_h.fetch(:recordable_registrations).fetch("Page")

    assert_equal "Page", registration.fetch(:recordable_type)
    assert_equal true, registration.fetch(:serializer)
  end

  def test_configure_without_block_is_safe
    RecordingStudioApi.configure

    assert_kind_of RecordingStudioApi::Configuration, RecordingStudioApi.configuration
  end
end
