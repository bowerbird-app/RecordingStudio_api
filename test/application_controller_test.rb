# frozen_string_literal: true

require "test_helper"
require "action_controller"
require_relative "../app/controllers/recording_studio_api/application_controller"

class RecordingStudioApiApplicationControllerTest < Minitest::Test
  def setup
    @original_layout_name = RecordingStudioApi.configuration.layout_name
    @original_admin_layout_name = RecordingStudioApi.configuration.admin_layout_name
    @original_admin_dashboard_path_resolver = RecordingStudioApi.configuration.admin_dashboard_path_resolver
    @original_admin_requests_path_resolver = RecordingStudioApi.configuration.admin_requests_path_resolver
  end

  def teardown
    RecordingStudioApi.configuration.layout_name = @original_layout_name
    RecordingStudioApi.configuration.admin_layout_name = @original_admin_layout_name
    RecordingStudioApi.configuration.admin_dashboard_path_resolver = @original_admin_dashboard_path_resolver
    RecordingStudioApi.configuration.admin_requests_path_resolver = @original_admin_requests_path_resolver
  end

  def test_layout_uses_configured_layout_name
    RecordingStudioApi.configuration.layout_name = "flat_pack_sidebar"

    controller = RecordingStudioApi::ApplicationController.new

    assert_equal "flat_pack_sidebar", controller.send(:recording_studio_api_layout)
  end

  def test_layout_falls_back_to_application_when_layout_name_blank
    RecordingStudioApi.configuration.layout_name = ""

    controller = RecordingStudioApi::ApplicationController.new

    assert_equal "application", controller.send(:recording_studio_api_layout)
  end

  def test_admin_layout_uses_configured_admin_layout_name
    RecordingStudioApi.configuration.layout_name = "application"
    RecordingStudioApi.configuration.admin_layout_name = "flat_pack_sidebar"

    controller = RecordingStudioApi::ApplicationController.new

    assert_equal "flat_pack_sidebar", controller.send(:recording_studio_api_admin_layout)
  end

  def test_admin_layout_falls_back_to_standard_layout_when_blank
    RecordingStudioApi.configuration.layout_name = "flat_pack_sidebar"
    RecordingStudioApi.configuration.admin_layout_name = ""

    controller = RecordingStudioApi::ApplicationController.new

    assert_equal "flat_pack_sidebar", controller.send(:recording_studio_api_admin_layout)
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
end
