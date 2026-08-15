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

    assert_equal ["public"], configuration.api_names
    assert_same configuration.public_api, configuration.api(:public)
    assert_equal 5, configuration.timeout
    assert_equal 30.days, configuration.credential_ttl
    assert_equal 1.hour, configuration.access_token_ttl
    assert_equal [], configuration.token_authenticators
    assert_equal :view, configuration.access_management_view_role
    assert_equal :admin, configuration.access_management_edit_role
    assert_equal({}, configuration.capability_action_roles)
    assert_nil configuration.capability_action_role_resolver
    assert_respond_to configuration.admin_dashboard_path_resolver, :call
    assert_respond_to configuration.admin_requests_path_resolver, :call
    assert_respond_to configuration.admin_errors_path_resolver, :call
    assert_respond_to configuration.admin_logs_path_resolver, :call
    assert_nil configuration.admin_layout_name
    assert_equal ["v1"], configuration.api_versions
    assert_equal "v1", configuration.default_api_version
    assert_nil configuration.openapi_title
    assert_nil configuration.openapi_description
    assert_equal false, configuration.documentation_enabled
    assert_nil configuration.documentation_access
    assert_nil configuration.documentation_layout_name
    assert_equal "recording_studio/default_layout", configuration.layout_name
    assert_equal true, configuration.rate_limit_oauth_enabled
    assert_equal false, configuration.rate_limit_api_enabled
    assert_equal true, configuration.rate_limit_api_pre_auth_enabled
    assert_equal true, configuration.rate_limit_fail_closed
    assert_equal %w[oauth api_pre_auth], configuration.rate_limit_fail_closed_buckets
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
    assert_equal [], configuration.api_request_log_allowed_param_keys
    assert_equal 30, configuration.api_request_log_retention_days
    assert_nil configuration.api_daily_metric_retention_days
    assert_instance_of RecordingStudioApi::Hooks, configuration.hooks
  end

  def test_named_api_definitions_are_isolated_from_public_api
    operations_api = @configuration.api(:operations) do |api|
      api.api_versions = %w[v1 v2]
      api.default_api_version = "v2"
      api.openapi_title = "Operations API"
      api.recordable_registry.register("AdminRoot")
    end

    assert_equal %w[public operations], @configuration.api_names
    assert_equal "operations", operations_api.name
    assert_equal %w[v1 v2], operations_api.api_versions
    assert_equal "v2", operations_api.default_api_version
    assert_equal "Operations API", operations_api.openapi_title
    assert operations_api.recordable_registry["AdminRoot"]
    assert_nil @configuration.public_api.recordable_registry["AdminRoot"]
  end

  def test_documentation_requires_an_explicit_access_policy_when_enabled
    @configuration.documentation_enabled = true

    error = assert_raises(RecordingStudioApi::ConfigurationError) { @configuration.validate! }
    assert_includes error.message, "documentation_access"

    @configuration.documentation_access = :authenticated
    @configuration.validate!

    operations = @configuration.api(:operations)
    operations.documentation_enabled = true
    error = assert_raises(RecordingStudioApi::ConfigurationError) { @configuration.validate! }
    assert_includes error.message, "documentation_access"

    operations.documentation_access = ->(**) { true }
    @configuration.validate!
  end

  def test_named_api_policies_inherit_public_defaults_and_can_override_them
    @configuration.credential_ttl = 12.hours
    @configuration.access_token_ttl = 20.minutes
    @configuration.rate_limit_api_read_requests = 75
    @configuration.api_request_logging_payload_mode = "filtered"
    @configuration.api_request_log_allowed_param_keys = %w[query]

    operations_api = @configuration.api(:operations) do |api|
      api.api_management_authorization_required = true
      api.access_token_ttl = 5.minutes
      api.rate_limit_api_read_requests = 20
      api.api_request_log_allowed_param_keys << "cursor"
    end

    assert_equal 12.hours, operations_api.credential_ttl
    assert_equal 5.minutes, operations_api.access_token_ttl
    assert_equal 20, operations_api.rate_limit_api_read_requests
    assert_equal "filtered", operations_api.api_request_logging_payload_mode
    assert_equal %w[query cursor], operations_api.api_request_log_allowed_param_keys
    assert operations_api.api_management_authorization_required
    assert_equal 20.minutes, @configuration.access_token_ttl
    assert_equal 75, @configuration.rate_limit_api_read_requests
    assert_equal %w[query], @configuration.api_request_log_allowed_param_keys
    refute @configuration.api_management_authorization_required
  end

  def test_api_names_are_normalized_and_invalid_names_are_rejected
    assert_same @configuration.api("Operations API"), @configuration.api(:operations_api)

    assert_raises(RecordingStudioApi::ConfigurationError) { @configuration.api("../admin") }
    assert_raises(RecordingStudioApi::ConfigurationError) { @configuration.fetch_api(:missing) }
  end

  def test_module_facade_targets_named_api_without_leaking_to_public
    original_configuration = RecordingStudioApi.configuration
    RecordingStudioApi.instance_variable_set(:@configuration, @configuration)
    @configuration.api(:operations) { |api| api.api_versions = %w[v1 v2] }

    RecordingStudioApi.register_recordable_type_api("AdminRoot", api: :operations)

    assert_equal %w[v1 v2], RecordingStudioApi.api_versions(api: :operations)
    assert_equal ["AdminRoot"], RecordingStudioApi.api_recordable_types(api: :operations)
    assert RecordingStudioApi.recordable_registration_for("AdminRoot", api: :operations)
    assert_nil RecordingStudioApi.recordable_registration_for("AdminRoot")
  ensure
    RecordingStudioApi.instance_variable_set(:@configuration, original_configuration)
  end

  def test_default_resource_actions_are_registered_for_each_api
    original_configuration = RecordingStudioApi.configuration
    RecordingStudioApi.instance_variable_set(:@configuration, @configuration)
    @configuration.api(:operations)

    RecordingStudioApi.register_default_resource_actions!

    assert RecordingStudioApi.resource_action(:index)
    assert RecordingStudioApi.resource_action(:index, api: :operations)
  ensure
    RecordingStudioApi.instance_variable_set(:@configuration, original_configuration)
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
      credential_ttl: 14.days,
      access_token_ttl: 15.minutes,
      rate_limit_oauth_enabled: true,
      rate_limit_api_enabled: true,
      rate_limit_api_pre_auth_enabled: true,
      rate_limit_fail_closed: true,
      rate_limit_fail_closed_buckets: %i[oauth api_pre_auth],
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
      api_request_logging_payload_mode: "metadata_only",
      api_request_log_allowed_param_keys: %w[resource limit],
      api_request_log_retention_days: 14,
      api_daily_metric_retention_days: 365
    )

    assert_equal 14.days, @configuration.credential_ttl
    assert_equal 15.minutes, @configuration.access_token_ttl
    assert_equal true, @configuration.rate_limit_oauth_enabled
    assert_equal true, @configuration.rate_limit_api_enabled
    assert_equal true, @configuration.rate_limit_api_pre_auth_enabled
    assert_equal true, @configuration.rate_limit_fail_closed
    assert_equal %i[oauth api_pre_auth], @configuration.rate_limit_fail_closed_buckets
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
    assert_equal %w[resource limit], @configuration.api_request_log_allowed_param_keys
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
    assert_equal :edit, registration.fetch(:required_role)
    assert_equal ["1.2.3"], registration.fetch(:versions)
  end

  def test_capability_action_roles_normalizes_and_validates_host_overrides
    @configuration.capability_action_roles = { publish: "admin", "archive" => :view }

    assert_equal({ "publish" => :admin, "archive" => :view }, @configuration.capability_action_roles)
    assert_raises(RecordingStudioApi::ConfigurationError) do
      @configuration.capability_action_roles = { publish: :owner }
    end
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
      serializer: ->(*) { { title: "Title" } },
      output_keys: %i[title],
      writable_attributes: %i[title],
      openapi: { details_schema: { type: "object" } }
    )

    registration = @configuration.to_h.fetch(:recordable_registrations).fetch("Page")

    assert_equal "Page", registration.fetch(:recordable_type)
    assert_equal ["title"], registration.fetch(:output_keys)
    assert_equal({}, registration.fetch(:fields))
    assert_equal ["title"], registration.fetch(:writable_attributes)
    assert_equal %i[create destroy index show update], registration.fetch(:operations)
    assert_equal [], registration.fetch(:capability_actions)
  end

  def test_recordable_registration_accepts_a_capability_action_allowlist
    @configuration.recordable_registry.register("Page", capability_actions: %i[publish move])

    registration = @configuration.recordable_registry.fetch("Page")

    assert registration.supports_capability_action?(:publish)
    assert registration.supports_capability_action?(:move)
    refute registration.supports_capability_action?(:archive)
  end

  def test_recordable_registration_rejects_invalid_capability_action_names
    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      @configuration.recordable_registry.register("Page", capability_actions: ["not-valid"])
    end

    assert_equal "Capability actions are invalid for Page: not-valid", error.message
  end

  def test_capability_actions_require_a_recordable_specific_api_opt_in
    original_configuration_defined = RecordingStudioApi.instance_variable_defined?(:@configuration)
    original_configuration = RecordingStudioApi.instance_variable_get(:@configuration)
    RecordingStudioApi.instance_variable_set(:@configuration, @configuration)
    @configuration.action_registry.register(
      :publish,
      capability: :publishable,
      http_verb: :post,
      handler: ->(_context) { :ok }
    )
    @configuration.recordable_registry.register("Page")

    RecordingStudio.stub(:capability_enabled?, ->(capability, **kwargs) { capability == :publishable && kwargs[:for] == "Page" }) do
      assert_equal [], RecordingStudioApi.capability_actions_for("Page")

      @configuration.recordable_registry.register("Page", capability_actions: %i[publish])

      assert_equal ["publish"], RecordingStudioApi.capability_actions_for("Page").map(&:name)
    end
  ensure
    if original_configuration_defined
      RecordingStudioApi.instance_variable_set(:@configuration, original_configuration)
    elsif RecordingStudioApi.instance_variable_defined?(:@configuration)
      RecordingStudioApi.remove_instance_variable(:@configuration)
    end
  end

  def test_recordable_registration_accepts_an_operation_allowlist
    @configuration.recordable_registry.register("AuditLog", operations: %i[index show])

    registration = @configuration.recordable_registry.fetch("AuditLog")

    assert registration.supports_operation?(:index)
    assert registration.supports_operation?(:show)
    refute registration.supports_operation?(:create)
  end

  def test_recordable_registration_rejects_unknown_operations
    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      @configuration.recordable_registry.register("AuditLog", operations: %i[index export])
    end

    assert_equal "Unsupported API operations for AuditLog: export", error.message
  end

  def test_register_recordable_type_api_composes_multiple_registrations_for_same_type
    @configuration.recordable_registry.register(
      "Page",
      serializer: ->(*) { { title: "Title" } },
      output_keys: %i[title],
      writable_attributes: %i[title],
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
      fields: { summary: { resolver: ->(recordable) { "Summary: #{recordable.title}" } } },
      writable_attributes: %i[summary],
      openapi: {
        details_schema: {
          properties: {
            summary: { type: "string" }
          }
        }
      }
    )

    registration = @configuration.recordable_registry.fetch("Page")
    recordable = Struct.new(:title).new("Docs")

    assert_equal "Summary: Docs", registration.fields.fetch("summary").resolver.call(recordable)
    properties = registration.openapi.fetch(:details_schema).fetch(:properties)
    assert_equal "string", properties.fetch(:title).fetch(:type)
    assert_equal "string", properties.fetch(:summary).fetch(:type)
    assert_equal %w[summary title], registration.writable_attributes
    assert_equal [], registration.capability_actions
  end

  def test_configure_without_block_is_safe
    RecordingStudioApi.configure

    assert_kind_of RecordingStudioApi::Configuration, RecordingStudioApi.configuration
  end

  def test_validate_rejects_non_positive_access_token_ttl
    @configuration.access_token_ttl = 0

    error = assert_raises(RecordingStudioApi::ConfigurationError) { @configuration.validate! }

    assert_equal "access_token_ttl must be positive", error.message
  end

  def test_validate_rejects_negative_credential_ttl
    @configuration.credential_ttl = -1.second

    error = assert_raises(RecordingStudioApi::ConfigurationError) { @configuration.validate! }

    assert_equal "credential_ttl must be non-negative", error.message
  end

  def test_validate_allows_nil_credential_ttl
    @configuration.credential_ttl = nil

    @configuration.validate!
  end

  def test_validate_rejects_invalid_enabled_rate_limit_bucket
    @configuration.rate_limit_oauth_enabled = true
    @configuration.rate_limit_oauth_requests = 0

    error = assert_raises(RecordingStudioApi::ConfigurationError) { @configuration.validate! }

    assert_equal "rate_limit_oauth_requests must be positive when rate limiting is enabled", error.message
  end

  def test_validate_rejects_invalid_enabled_api_fallback_rate_limit
    @configuration.rate_limit_api_enabled = true
    @configuration.rate_limit_api_read_requests = 0
    @configuration.rate_limit_api_requests = 0

    error = assert_raises(RecordingStudioApi::ConfigurationError) { @configuration.validate! }

    assert_equal "rate_limit_api_read_requests must be positive when rate limiting is enabled", error.message
  end

  def test_validate_rejects_negative_enabled_api_rate_limit_override
    @configuration.rate_limit_api_enabled = true
    @configuration.rate_limit_api_write_requests = -1

    error = assert_raises(RecordingStudioApi::ConfigurationError) { @configuration.validate! }

    assert_equal "rate_limit_api_write_requests must be positive when rate limiting is enabled", error.message
  end

  def test_validate_rejects_invalid_configured_retention_duration
    @configuration.api_request_log_retention_days = 0

    error = assert_raises(RecordingStudioApi::ConfigurationError) { @configuration.validate! }

    assert_equal "api_request_log_retention_days must be positive when configured", error.message
  end
end
