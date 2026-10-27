# frozen_string_literal: true

require "test_helper"
require "action_controller"
require_relative "../app/controllers/recording_studio_api/application_controller"

class RecordingStudioApiApplicationControllerTest < Minitest::Test
  def setup
    @original_layout = RecordingStudioApi.configuration.layout
    @original_layout_name = RecordingStudioApi.configuration.layout_name
    @original_admin_layout_name = RecordingStudioApi.configuration.admin_layout_name
    @original_admin_dashboard_path_resolver = RecordingStudioApi.configuration.admin_dashboard_path_resolver
    @original_admin_requests_path_resolver = RecordingStudioApi.configuration.admin_requests_path_resolver
    @original_admin_errors_path_resolver = RecordingStudioApi.configuration.admin_errors_path_resolver
  end

  def teardown
    RecordingStudioApi.configuration.layout_name = @original_layout_name
    RecordingStudioApi.configuration.layout = @original_layout
    RecordingStudioApi.configuration.admin_layout_name = @original_admin_layout_name
    RecordingStudioApi.configuration.admin_dashboard_path_resolver = @original_admin_dashboard_path_resolver
    RecordingStudioApi.configuration.admin_requests_path_resolver = @original_admin_requests_path_resolver
    RecordingStudioApi.configuration.admin_errors_path_resolver = @original_admin_errors_path_resolver
  end

  def test_layout_uses_configured_layout
    RecordingStudioApi.configuration.layout = "flat_pack_sidebar"

    controller = RecordingStudioApi::ApplicationController.new

    assert_equal "flat_pack_sidebar", controller.recording_studio_resolved_layout
  end

  def test_blank_layout_uses_recording_studio_default
    RecordingStudioApi.configuration.layout = nil

    controller = RecordingStudioApi::ApplicationController.new

    assert_equal "recording_studio/default_layout", controller.recording_studio_resolved_layout
  end

  def test_layout_false_skips_the_layout
    RecordingStudioApi.configuration.layout = false

    controller = RecordingStudioApi::ApplicationController.new

    assert_equal false, controller.recording_studio_resolved_layout
  end

  def test_layout_callable_receives_the_controller
    RecordingStudioApi.configuration.layout = ->(controller:) { controller.class.name }

    controller = RecordingStudioApi::ApplicationController.new

    assert_equal "RecordingStudioApi::ApplicationController", controller.recording_studio_resolved_layout
  end

  def test_admin_layout_overrides_the_shared_layout
    RecordingStudioApi.configuration.layout = "application"
    RecordingStudioApi.configuration.admin_layout_name = "flat_pack_sidebar"
    require_relative "../app/controllers/recording_studio_api/admin_controller"

    controller = RecordingStudioApi::AdminController.new

    assert_equal "flat_pack_sidebar", controller.recording_studio_resolved_layout
  end

  def test_admin_layout_inherits_the_shared_layout_when_blank
    RecordingStudioApi.configuration.layout = "flat_pack_sidebar"
    RecordingStudioApi.configuration.admin_layout_name = ""
    require_relative "../app/controllers/recording_studio_api/admin_controller"

    controller = RecordingStudioApi::AdminController.new

    assert_equal "flat_pack_sidebar", controller.recording_studio_resolved_layout
  end

  def test_scalar_docs_layout_uses_the_api_override
    RecordingStudioApi.configuration.layout = "application"
    require_relative "../app/controllers/recording_studio_api/scalar_docs_controller"
    controller = RecordingStudioApi::ScalarDocsController.new
    controller.instance_variable_set(:@api_definition, Struct.new(:documentation_layout_name).new("portal"))

    assert_equal "portal", controller.recording_studio_resolved_layout
  end

  def test_scalar_docs_layout_inherits_when_the_api_override_is_blank
    RecordingStudioApi.configuration.layout = "application"
    require_relative "../app/controllers/recording_studio_api/scalar_docs_controller"
    controller = RecordingStudioApi::ScalarDocsController.new
    controller.instance_variable_set(:@api_definition, Struct.new(:documentation_layout_name).new(""))

    assert_equal "application", controller.recording_studio_resolved_layout
  end

  def test_admin_dashboard_path_uses_configured_resolver
    main_app = Struct.new(:admin_api_path).new("/admin/api")
    controller = Struct.new(:main_app, :recording_studio_api).new(main_app, nil)

    RecordingStudioApi.configuration.admin_dashboard_path_resolver = ->(controller:, **) { controller.main_app.admin_api_path }

    assert_equal "/admin/api", RecordingStudioApi.admin_dashboard_path(controller: controller)
  end

  def test_admin_requests_path_uses_configured_resolver
    main_app = Struct.new(:admin_api_requests_path).new("/admin/api/requests")
    controller = Struct.new(:main_app, :recording_studio_api).new(main_app, nil)

    RecordingStudioApi.configuration.admin_requests_path_resolver = ->(controller:, **) { controller.main_app.admin_api_requests_path }

    assert_equal "/admin/api/requests", RecordingStudioApi.admin_requests_path(controller: controller)
  end

  def test_admin_errors_path_uses_configured_resolver
    main_app = Struct.new(:admin_api_errors_path).new("/admin/api/errors")
    controller = Struct.new(:main_app, :recording_studio_api).new(main_app, nil)

    RecordingStudioApi.configuration.admin_errors_path_resolver = ->(controller:, **) { controller.main_app.admin_api_errors_path }

    assert_equal "/admin/api/errors", RecordingStudioApi.admin_errors_path(controller: controller)
  end
end
