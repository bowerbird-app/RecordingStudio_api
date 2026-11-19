# frozen_string_literal: true

require "test_helper"

class EngineTest < Minitest::Test
  def setup
    @original_configuration = RecordingStudioApi.instance_variable_get(:@configuration)
    RecordingStudioApi.instance_variable_set(:@configuration, RecordingStudioApi::Configuration.new)
  end

  def teardown
    RecordingStudioApi.configuration.hooks.clear!
    RecordingStudioApi.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_before_and_after_initialize_initializers_run_hooks
    before_called = false
    after_called = false

    RecordingStudioApi.configuration.hooks.before_initialize { |_engine| before_called = true }
    RecordingStudioApi.configuration.hooks.after_initialize { |_engine| after_called = true }

    find_initializer("recording_studio_api.before_initialize").block.call(Object.new)
    find_initializer("recording_studio_api.after_initialize").block.call(Object.new)

    assert before_called
    assert after_called
  end

  def test_load_config_merges_config_sources_and_runs_on_configuration_hook
    hook_called = false
    hook_payload = nil
    RecordingStudioApi.configuration.hooks.on_configuration do |cfg|
      hook_called = true
      hook_payload = cfg
    end

    xcfg = Struct.new(:recording_studio_api).new({ rate_limit_api_enabled: true })
    app_config = Struct.new(:x).new(xcfg)
    app = Struct.new(:config) do
      def config_for(_name)
        { timeout: 12 }
      end
    end.new(app_config)

    find_initializer("recording_studio_api.load_config").block.call(app)

    assert hook_called
    assert_equal RecordingStudioApi.configuration, hook_payload
    assert_equal 12, RecordingStudioApi.configuration.timeout
    assert_equal true, RecordingStudioApi.configuration.rate_limit_api_enabled
  end

  def test_load_config_raises_when_yaml_cannot_load
    app = Struct.new(:config) do
      def config_for(_name)
        raise "missing file"
      end
    end.new(Object.new)

    error = assert_raises(RuntimeError) do
      find_initializer("recording_studio_api.load_config").block.call(app)
    end

    assert_equal "missing file", error.message
  end

  def test_load_config_merges_each_pair_when_config_has_no_to_h
    pair_config = Class.new do
      def each_pair
        yield(:timeout, 15)
      end
    end.new

    xcfg = Struct.new(:recording_studio_api).new(pair_config)
    app_config = Struct.new(:x).new(xcfg)
    app = Struct.new(:config) do
      def config_for(_name)
        { timeout: 8 }
      end
    end.new(app_config)

    find_initializer("recording_studio_api.load_config").block.call(app)

    assert_equal 15, RecordingStudioApi.configuration.timeout
  end

  def test_load_config_raises_when_each_pair_fails
    bad_pair_config = Class.new do
      def each_pair
        raise "bad pair"
      end
    end.new

    xcfg = Struct.new(:recording_studio_api).new(bad_pair_config)
    app_config = Struct.new(:x).new(xcfg)
    app = Struct.new(:config) do
      def config_for(_name)
        { timeout: 8 }
      end
    end.new(app_config)

    error = assert_raises(RuntimeError) do
      find_initializer("recording_studio_api.load_config").block.call(app)
    end

    assert_equal "bad pair", error.message
    assert_equal 8, RecordingStudioApi.configuration.timeout
  end

  def test_load_config_is_noop_without_config_sources
    app = Struct.new(:config).new(Object.new)

    find_initializer("recording_studio_api.load_config").block.call(app)

    assert_equal 5, RecordingStudioApi.configuration.timeout
    assert_equal true, RecordingStudioApi.configuration.rate_limit_api_enabled
    assert_equal %w[oauth api_pre_auth api_failed_auth], RecordingStudioApi.configuration.rate_limit_fail_closed_buckets
  end

  def test_load_config_raises_when_yaml_each_fails
    yaml = Class.new do
      def each
        raise "bad yaml"
      end
    end.new

    xcfg = Struct.new(:recording_studio_api).new({ timeout: 22 })
    app_config = Struct.new(:x).new(xcfg)
    app = Struct.new(:config) do
      attr_accessor :yaml

      def config_for(_name)
        @yaml
      end
    end.new(app_config)
    app.yaml = yaml

    error = assert_raises(RuntimeError) do
      find_initializer("recording_studio_api.load_config").block.call(app)
    end

    assert_equal "bad yaml", error.message
  end

  def test_apply_extension_initializers_register_active_support_on_load_callbacks
    to_prepare_blocks = []
    config_stub = Object.new
    config_stub.define_singleton_method(:to_prepare) do |&block|
      to_prepare_blocks << block
    end

    RecordingStudioApi::Engine.stub(:config, config_stub) do
      find_initializer("recording_studio_api.apply_model_extensions").block.call
      find_initializer("recording_studio_api.apply_controller_extensions").block.call
    end

    assert_equal 2, to_prepare_blocks.size
  end

  def test_model_extension_initializer_skips_abstract_models
    to_prepare_blocks = []
    config_stub = Object.new
    config_stub.define_singleton_method(:to_prepare) do |&block|
      to_prepare_blocks << block
    end

    abstract_model = Class.new do
      def self.abstract_class?
        true
      end
    end
    concrete_model = Class.new do
      def self.abstract_class?
        false
      end
    end
    applied = []
    active_record_base = Class.new
    active_record_base.define_singleton_method(:descendants) { [abstract_model, concrete_model] }

    RecordingStudioApi::Engine.stub(:config, config_stub) do
      find_initializer("recording_studio_api.apply_model_extensions").block.call
    end

    with_temporary_nested_constant(:ActiveRecord, :Base, active_record_base) do
      RecordingStudioApi::Engine.stub(:apply_model_extensions, ->(model) { applied << model }) do
        to_prepare_blocks.first.call
      end
    end

    assert_equal [concrete_model], applied
  end

  def test_apply_loaded_controller_extensions_reaches_base_and_api_controllers
    require "action_controller"
    base_parent = ActionController::Base
    api_parent = ActionController::API

    base_controller = Class.new(base_parent) do
      def self.name
        "PreparedBaseController"
      end
    end
    api_controller = Class.new(api_parent) do
      def self.name
        "PreparedApiController"
      end
    end

    RecordingStudioApi.configuration.hooks.extend_controller(:PreparedBaseController) do
      def prepared_base_extension
        :applied
      end
    end
    RecordingStudioApi.configuration.hooks.extend_controller(:PreparedApiController) do
      def prepared_api_extension
        :applied
      end
    end

    refute base_controller.method_defined?(:prepared_base_extension)
    refute api_controller.method_defined?(:prepared_api_extension)

    RecordingStudioApi::Engine.apply_loaded_controller_extensions

    assert base_controller.method_defined?(:prepared_base_extension)
    assert api_controller.method_defined?(:prepared_api_extension)
  end

  def test_apply_model_extensions_adds_registered_methods_once
    model_class = Class.new do
      def self.name
        "ExampleRecord"
      end
    end

    RecordingStudioApi.configuration.hooks.extend_model(:ExampleRecord) do
      def template_extension_method
        :applied
      end
    end

    RecordingStudioApi::Engine.apply_model_extensions(model_class)
    RecordingStudioApi::Engine.apply_model_extensions(model_class)

    instance = model_class.new
    assert_equal :applied, instance.template_extension_method
  end

  def test_apply_controller_extensions_matches_demodulized_name
    controller_class = Class.new do
      def self.name
        "Admin::DashboardController"
      end
    end

    RecordingStudioApi.configuration.hooks.extend_controller(:DashboardController) do
      def template_controller_extension
        :applied
      end
    end

    RecordingStudioApi::Engine.apply_controller_extensions(controller_class)

    instance = controller_class.new
    assert_equal :applied, instance.template_controller_extension
  end

  def test_apply_model_extensions_loads_every_name
    model_class = Class.new do
      def self.name
        "Admin::ExampleRecord"
      end
    end

    RecordingStudioApi.configuration.hooks.extend_model(:"Admin::ExampleRecord") do
      def full_name_extension
        :full
      end
    end
    RecordingStudioApi.configuration.hooks.extend_model(:ExampleRecord) do
      def short_name_extension
        :short
      end
    end

    RecordingStudioApi::Engine.apply_model_extensions(model_class)

    instance = model_class.new
    assert_equal :full, instance.full_name_extension
    assert_equal :short, instance.short_name_extension
  end

  def test_moveable_conflict_extension_installs_on_api_controller
    move = RecordingStudio::Moveable::Api::MoveRecording
    previous = move.instance_variable_get(:@conflict_response_installed)
    move.instance_variable_set(:@conflict_response_installed, false)
    move.install_conflict_response!

    controller = Class.new do
      def self.name
        "RecordingStudioApi::ApiController"
      end

      def self.rescue_from(exception_class, &handler)
        @handlers ||= []
        @handlers << [exception_class, handler]
      end

      def self.handlers
        @handlers || []
      end
    end

    RecordingStudioApi::Engine.apply_controller_extensions(controller)
    exception_class, handler = controller.handlers.assoc(RecordingStudio::Moveable::Api::Conflict)
    assert_equal RecordingStudio::Moveable::Api::Conflict, exception_class

    rendered = nil
    target = controller.new
    target.define_singleton_method(:render_error) { |**kwargs| rendered = kwargs }
    error = RecordingStudio::Moveable::Api::Conflict.new("Tree changed", details: ["Tree changed"])
    target.instance_exec(error, &handler)

    assert_equal "conflict", rendered.fetch(:code)
    assert_equal :conflict, rendered.fetch(:status)
    assert_equal 409, Rack::Utils.status_code(rendered.fetch(:status))
  ensure
    move.instance_variable_set(:@conflict_response_installed, previous)
  end

  def test_applying_an_extension_twice_does_not_duplicate_the_rescue
    require "action_controller"
    controller = Class.new(ActionController::API) do
      def self.name
        "OnceApiController"
      end
    end

    RecordingStudioApi.configuration.hooks.extend_controller(:OnceApiController) do
      rescue_from StandardError do
        # The handler body is unused. The count is the assertion.
      end
    end

    RecordingStudioApi::Engine.apply_controller_extensions(controller)
    RecordingStudioApi::Engine.apply_controller_extensions(controller)

    assert_equal 1, controller.rescue_handlers.map(&:first).count("StandardError")
  end

  def test_distinct_extensions_with_the_same_effect_both_apply
    require "action_controller"
    controller = Class.new(ActionController::API) do
      def self.name
        "EqualProcsController"
      end
    end

    RecordingStudioApi.configuration.hooks.extend_controller(:EqualProcsController) do
      rescue_from ArgumentError do
        # First of two equal rescues.
      end
    end
    RecordingStudioApi.configuration.hooks.extend_controller(:EqualProcsController) do
      rescue_from ArgumentError do
        # Second of two equal rescues.
      end
    end

    RecordingStudioApi::Engine.apply_controller_extensions(controller)

    assert_equal 2, controller.rescue_handlers.map(&:first).count("ArgumentError")
  end

  def test_a_later_failure_does_not_replay_an_applied_extension
    controller = Class.new do
      def self.name
        "PartialApplyController"
      end

      class << self
        attr_accessor :runs
      end
    end
    controller.runs = 0

    RecordingStudioApi.configuration.hooks.extend_controller(:PartialApplyController) do
      controller.runs += 1
    end
    RecordingStudioApi.configuration.hooks.extend_controller(:PartialApplyController) do
      raise "stop applying"
    end

    assert_raises(RuntimeError) { RecordingStudioApi::Engine.apply_controller_extensions(controller) }
    assert_raises(RuntimeError) { RecordingStudioApi::Engine.apply_controller_extensions(controller) }

    assert_equal 1, controller.runs
  end

  def test_apply_extensions_returns_without_target
    assert_nil RecordingStudioApi::Engine.send(:apply_extensions, nil, [])
  end

  def test_extension_keys_for_includes_demodulized_name
    namespaced = Class.new do
      def self.name
        "Admin::ReportsController"
      end
    end

    expected_keys = [:"Admin::ReportsController"]
    expected_keys << :ReportsController

    assert_equal expected_keys, RecordingStudioApi::Engine.send(:extension_keys_for, namespaced)
  end

  def test_extension_keys_for_removes_duplicate_names
    plain = Class.new do
      def self.name
        "ReportsController"
      end
    end

    assert_equal [:ReportsController], RecordingStudioApi::Engine.send(:extension_keys_for, plain)
  end

  def test_complete_request_clears_admin_credential_cache_when_admin_is_loaded
    require "recording_studio_api/admin/queries/admin_api_credentials_query"

    cleared = false
    RecordingStudioApi::Admin.stub(:available?, true) do
      RecordingStudioApi::Admin::Queries::AdminApiCredentialsQuery.stub(:clear_cache!, -> { cleared = true }) do
        RecordingStudioApi::Engine.complete_request!
      end
    end

    assert cleared
  end

  def test_complete_request_skips_admin_queries_when_admin_is_absent
    queries_defined = RecordingStudioApi::Admin.const_defined?(:Queries, false)
    queries = RecordingStudioApi::Admin.send(:remove_const, :Queries) if queries_defined

    RecordingStudioApi::Admin.stub(:available?, false) do
      assert_nil RecordingStudioApi::Engine.complete_request!
    end
  ensure
    RecordingStudioApi::Admin.const_set(:Queries, queries) if queries_defined
  end

  def test_complete_request_does_not_swallow_admin_cache_errors
    require "recording_studio_api/admin/queries/admin_api_credentials_query"

    RecordingStudioApi::Admin.stub(:available?, true) do
      RecordingStudioApi::Admin::Queries::AdminApiCredentialsQuery.stub(:clear_cache!, -> { raise "cache failed" }) do
        error = assert_raises(RuntimeError) { RecordingStudioApi::Engine.complete_request! }
        assert_equal "cache failed", error.message
      end
    end
  end

  def test_request_completion_callback_runs_complete_request
    require "active_support/executor"

    calls = 0
    RecordingStudioApi::Engine.stub(:complete_request!, -> { calls += 1 }) do
      find_initializer("recording_studio_api.flush_request_log_batches").block.call
      ActiveSupport::Executor.wrap { nil }
    end

    assert_operator calls, :>=, 1
  end

  def test_register_default_capability_actions_delegates_move_to_moveable
    RecordingStudioApi.register_default_capability_actions!

    action = RecordingStudioApi.capability_action(:move)
    assert_equal :movable, action.capability
    assert_equal RecordingStudio::Moveable::Api::MoveRecording, action.handler
    assert_equal "1.0.0", action.version.to_s
  end

  def test_register_default_resource_actions_adds_core_resource_operations
    RecordingStudioApi.register_default_resource_actions!

    assert_equal :collection, RecordingStudioApi.resource_action(:index).scope
    assert_equal :resource, RecordingStudioApi.resource_action(:show).scope
    assert_equal :collection, RecordingStudioApi.resource_action(:create).scope
    assert_equal :resource, RecordingStudioApi.resource_action(:update).scope
    assert_equal :resource, RecordingStudioApi.resource_action(:destroy).scope
  end

  def test_capability_actions_for_excludes_core_resource_operations
    RecordingStudioApi.register_default_resource_actions!

    assert_equal [], RecordingStudioApi.capability_actions_for("Workspace")
  end

  private

  def with_temporary_nested_constant(parent_name, child_name, value)
    parent_defined = Object.const_defined?(parent_name, false)
    parent = parent_defined ? Object.const_get(parent_name) : Object.const_set(parent_name, Module.new)
    child_defined = parent.const_defined?(child_name, false)
    previous_child = parent.const_get(child_name) if child_defined

    parent.const_set(child_name, value)
    yield
  ensure
    parent.send(:remove_const, child_name) if parent.const_defined?(child_name, false)
    parent.const_set(child_name, previous_child) if child_defined
    Object.send(:remove_const, parent_name) unless parent_defined
  end

  def find_initializer(name)
    RecordingStudioApi::Engine.initializers.find { |initializer| initializer.name == name }
  end
end
