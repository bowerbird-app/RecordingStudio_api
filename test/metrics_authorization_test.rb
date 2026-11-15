# frozen_string_literal: true

require_relative "support/api_dummy_helpers"

class MetricsAuthorizationTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    configure_dummy_operations_api!
    RecordingStudioMetrics.registry.reset!
    RecordingStudioApi::Metrics.register!
    RecordingStudioApi::AdminApi.delete_all
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "site admin with view access sees api request and key metrics" do
    viewer = create_user
    _admin_root, admin_recording = site_admin_recording
    create_access_recording(parent_recording: admin_recording, user: viewer, role: :view)
    workspace_root, = create_access_recording_for(user: create_user)

    assert_equal true, authorize_metric(:api_requests, viewer, root_recording: workspace_root)
    assert_equal true, authorize_metric(:api_keys, viewer, root_recording: workspace_root)
  end

  test "non-admin is denied site metrics" do
    site_admin_recording
    outsider = create_user
    workspace_root, = create_access_recording_for(user: outsider, role: :admin)

    assert_equal false, authorize_metric(:api_requests, outsider, root_recording: workspace_root)
    assert_equal false, authorize_metric(:api_keys, outsider, root_recording: workspace_root)
  end

  test "raising site admin resolver denies metrics without an error" do
    viewer = create_user
    _admin_root, admin_recording = site_admin_recording
    create_access_recording(parent_recording: admin_recording, user: viewer, role: :view)
    config = RecordingStudioAccessible.configuration
    original_resolver = config.admin_root_resolver
    config.admin_root_resolver = ->(*) { raise NoMethodError, "undefined method `controller' for nil" }

    assert_nothing_raised do
      assert_equal false, authorize_metric(:api_requests, viewer, root_recording: admin_recording)
      assert_equal false, authorize_metric(:api_keys, viewer, root_recording: admin_recording)
    end
  ensure
    config.admin_root_resolver = original_resolver if defined?(config) && config && defined?(original_resolver)
  end

  private

  def site_admin_recording
    if defined?(Admin) && Admin.respond_to?(:find_or_create_by!) && Admin.column_names.include?("name")
      recordable = Admin.find_or_create_by!(name: "Admin")
      return [recordable, RecordingStudio::Recording.find_or_create_by!(recordable: recordable)]
    end

    create_admin_root_recording(name: "Admin")
  end

  def authorize_metric(resource, actor, root_recording:)
    hook = RecordingStudioMetrics.registry.api_authorize_for(resource)
    flunk "missing api_authorize for #{resource}" if hook.nil?

    grant = Struct.new(:actor).new(actor)
    context = Struct.new(:access_grant, :root_recording, :api_key).new(grant, root_recording, :operations)
    hook.call(context)
  end
end
