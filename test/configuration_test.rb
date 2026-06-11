# frozen_string_literal: true

require "test_helper"
require "ostruct"

class ConfigurationTest < Minitest::Test
  def setup
    @configuration = RecordingStudioApi::Configuration.new
  end

  def test_merge_updates_known_attributes
    @configuration.merge!(timeout: 9, rate_limit_api_enabled: true)

    assert_equal 9, @configuration.timeout
    assert_equal true, @configuration.rate_limit_api_enabled
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
    assert_equal original[:rate_limit_api_enabled], @configuration.rate_limit_api_enabled
  end

  def test_initialize_uses_defaults
    configuration = RecordingStudioApi::Configuration.new

    assert_equal 5, configuration.timeout
    assert_equal [], configuration.token_authenticators
    assert_equal :view, configuration.access_management_view_role
    assert_equal :admin, configuration.access_management_edit_role
    assert_respond_to configuration.admin_dashboard_path_resolver, :call
    assert_respond_to configuration.admin_requests_path_resolver, :call
    assert_respond_to configuration.admin_errors_path_resolver, :call
    assert_respond_to configuration.admin_logs_path_resolver, :call
    assert_nil configuration.admin_layout_name
    assert_equal ["v1"], configuration.api_versions
    assert_equal "v1", configuration.default_api_version
    assert_nil configuration.openapi_title
    assert_nil configuration.openapi_description
    assert_equal "application", configuration.layout_name
    assert_equal false, configuration.rate_limit_oauth_enabled
    assert_equal false, configuration.rate_limit_api_enabled
    assert_equal "recording_studio_api", configuration.rate_limit_redis_namespace
    assert_equal 10, configuration.rate_limit_oauth_requests
    assert_equal 60, configuration.rate_limit_oauth_period_seconds
    assert_equal 120, configuration.rate_limit_api_requests
    assert_equal 60, configuration.rate_limit_api_period_seconds
    assert_equal 120, configuration.rate_limit_api_read_requests
    assert_equal 60, configuration.rate_limit_api_read_period_seconds
    assert_equal 30, configuration.rate_limit_api_write_requests
    assert_equal 60, configuration.rate_limit_api_write_period_seconds
    assert_equal false, configuration.api_request_logging_enabled
    assert_equal "metadata_only", configuration.api_request_logging_payload_mode
    assert_instance_of RecordingStudioApi::Hooks, configuration.hooks
  end

  def test_register_token_authenticator_adds_callable_to_configuration
    authenticator = ->(token:) {}

    RecordingStudioApi.register_token_authenticator(authenticator)

    assert_includes RecordingStudioApi.token_authenticators, authenticator
  ensure
    RecordingStudioApi.instance_variable_set(:@configuration, RecordingStudioApi::Configuration.new)
  end

  def test_register_token_authenticator_requires_callable
    error = assert_raises(ArgumentError) do
      RecordingStudioApi.register_token_authenticator(nil)
    end

    assert_includes error.message, "callable"
  end

  def test_merge_updates_rate_limit_and_logging_settings
    @configuration.merge!(
      rate_limit_oauth_enabled: true,
      rate_limit_api_enabled: true,
      rate_limit_redis_namespace: "custom_ns",
      rate_limit_oauth_requests: 10,
      rate_limit_oauth_period_seconds: 30,
      rate_limit_api_requests: 90,
      rate_limit_api_period_seconds: 45,
      rate_limit_api_read_requests: 150,
      rate_limit_api_read_period_seconds: 25,
      rate_limit_api_write_requests: 40,
      rate_limit_api_write_period_seconds: 20,
      api_request_logging_enabled: true,
      api_request_logging_payload_mode: "metadata_only"
    )

    assert_equal true, @configuration.rate_limit_oauth_enabled
    assert_equal true, @configuration.rate_limit_api_enabled
    assert_equal "custom_ns", @configuration.rate_limit_redis_namespace
    assert_equal 10, @configuration.rate_limit_oauth_requests
    assert_equal 30, @configuration.rate_limit_oauth_period_seconds
    assert_equal 90, @configuration.rate_limit_api_requests
    assert_equal 45, @configuration.rate_limit_api_period_seconds
    assert_equal 150, @configuration.rate_limit_api_read_requests
    assert_equal 25, @configuration.rate_limit_api_read_period_seconds
    assert_equal 40, @configuration.rate_limit_api_write_requests
    assert_equal 20, @configuration.rate_limit_api_write_period_seconds
    assert_equal true, @configuration.api_request_logging_enabled
    assert_equal "metadata_only", @configuration.api_request_logging_payload_mode
  end

  def test_merge_updates_access_management_roles
    @configuration.merge!(access_management_view_role: "edit", access_management_edit_role: "admin")

    assert_equal :edit, @configuration.access_management_view_role
    assert_equal :admin, @configuration.access_management_edit_role
  end

  def test_merge_updates_openapi_title
    @configuration.merge!(openapi_title: "My API")

    assert_equal "My API", @configuration.openapi_title
  end

  def test_merge_updates_openapi_description
    @configuration.merge!(openapi_description: "Public endpoints for mobile clients")

    assert_equal "Public endpoints for mobile clients", @configuration.openapi_description
  end

  def test_merge_normalizes_api_versions_and_default
    @configuration.merge!(api_versions: %w[1 V2], default_api_version: "2")

    assert_equal %w[v1 v2], @configuration.api_versions
    assert_equal "v2", @configuration.default_api_version
  end

  def test_merge_includes_default_api_version_when_not_present
    @configuration.merge!(api_versions: ["v2"], default_api_version: "v9")

    assert_equal %w[v2 v9], @configuration.api_versions
    assert_equal "v9", @configuration.default_api_version
  end

  def test_merge_accepts_string_keys
    @configuration["timeout"] = 12

    assert_equal 12, @configuration.timeout
  end

  def test_merge_updates_layout_name
    @configuration.merge!(layout_name: "flat_pack_sidebar")

    assert_equal "flat_pack_sidebar", @configuration.layout_name
  end

  def test_merge_updates_admin_layout_name
    @configuration.merge!(admin_layout_name: "flat_pack_sidebar")

    assert_equal "flat_pack_sidebar", @configuration.admin_layout_name
  end

  def test_merge_updates_admin_dashboard_path_resolver
    resolver = ->(controller:, **) { controller.main_app.admin_api_path }

    @configuration.merge!(admin_dashboard_path_resolver: resolver)

    assert_equal resolver, @configuration.admin_dashboard_path_resolver
  end

  def test_merge_updates_admin_logs_path_resolver
    resolver = ->(controller:, **) { controller.main_app.admin_api_logs_path }

    @configuration.merge!(admin_logs_path_resolver: resolver)

    assert_equal resolver, @configuration.admin_logs_path_resolver
  end

  def test_merge_updates_admin_requests_path_resolver
    resolver = ->(controller:, **) { controller.main_app.admin_api_requests_path }

    @configuration.merge!(admin_requests_path_resolver: resolver)

    assert_equal resolver, @configuration.admin_requests_path_resolver
  end

  def test_merge_updates_admin_errors_path_resolver
    resolver = ->(controller:, **) { controller.main_app.admin_api_errors_path }

    @configuration.merge!(admin_errors_path_resolver: resolver)

    assert_equal resolver, @configuration.admin_errors_path_resolver
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
      version: "1.2.3",
      version_notes: ["Initial public echo contract"],
      deprecation: {
        deprecated: true,
        removal_date: "2026-12-31",
        reason: "Replaced by echo v2"
      },
      handler: ->(_context) { :ok }
    )

    registration = @configuration.to_h.fetch(:action_registrations).fetch("echo")
    assert_equal :echoable, registration.fetch(:action)
    assert_equal "1.2.3", registration.fetch(:version)
    assert_equal ["Initial public echo contract"], registration.fetch(:version_notes)
    assert_equal true, registration.fetch(:deprecation).fetch(:deprecated)
    assert_equal "2026-12-31", registration.fetch(:deprecation).fetch(:removal_date)
    assert_equal "Replaced by echo v2", registration.fetch(:deprecation).fetch(:reason)
    assert_equal ["1.2.3"], registration.fetch(:versions)
  end

  def test_version_profile_dsl_tracks_contribution_requirements
    profile = @configuration.version("2") do |api|
      api.use :moveable, "~> 2.0"
      api.use :publishable
    end

    assert_equal "v2", profile.name
    assert_includes @configuration.api_versions, "v2"
    assert_equal "~> 2.0", @configuration.api_version_profile_for("v2").requirements.fetch(:moveable).to_s
    assert_equal ">= 0", @configuration.api_version_profile_for("2").requirements.fetch(:publishable).to_s
    assert_equal "~> 2.0", @configuration.to_h.fetch(:api_version_profiles).fetch("v2").fetch(:requirements).fetch(:moveable)
  end

  def test_action_registry_resolves_highest_matching_contribution_version
    @configuration.action_registry.register(
      :echo,
      capability: :echoable,
      version: "1.5.0",
      handler: ->(_context) { :v1 }
    )
    @configuration.action_registry.register(
      :echo,
      capability: :echoable,
      version: "2.0.0",
      handler: ->(_context) { :v2 }
    )

    @configuration.version("v1") { |api| api.use :echoable, "~> 1.0" }
    @configuration.version("v2") { |api| api.use :echoable }

    assert_equal "1.5.0", @configuration.action_registry.resolve(:echo, profile: @configuration.api_version_profile_for("v1")).version.to_s
    assert_equal "2.0.0", @configuration.action_registry.resolve(:echo, profile: @configuration.api_version_profile_for("v2")).version.to_s
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

  def test_register_recordable_type_api_composes_multiple_registrations_for_same_type
    @configuration.recordable_registry.register(
      "Page",
      serializer: ->(recordable) { { title: recordable.title } },
      openapi: {
        details_schema: {
          properties: {
            title: { type: "string" }
          }
        }
      }
    )

    @configuration.recordable_registry.register(
      "Page",
      serializer: ->(recordable) { { summary: "Summary: #{recordable.title}" } },
      openapi: {
        details_schema: {
          properties: {
            summary: { type: "string" }
          }
        }
      }
    )

    registration = @configuration.recordable_registry.fetch("Page")
    payload = registration.serializer.call(Struct.new(:title).new("Docs"))

    assert_equal({ title: "Docs", summary: "Summary: Docs" }, payload)
    properties = registration.openapi.fetch(:details_schema).fetch(:properties)
    assert_equal "string", properties.fetch(:title).fetch(:type)
    assert_equal "string", properties.fetch(:summary).fetch(:type)
  end

  def test_configure_without_block_is_safe
    RecordingStudioApi.configure

    assert_kind_of RecordingStudioApi::Configuration, RecordingStudioApi.configuration
  end
end
