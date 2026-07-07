# frozen_string_literal: true

require_relative "support/api_dummy_helpers"

class RecordableDeclarationContractTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    RecordingStudioAccessible::Compatibility.register_access_capability!
    RecordingStudioAccessible::Compatibility.ensure_recordable_types_registered!
    RecordingStudioApi::Engine.register_recordable_types!
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "dummy app and api engine satisfy RecordingStudio declaration enforcement" do
    assert RecordingStudio.validate_recordable_declarations!
  end

  test "dummy app exposes root and child recordable hierarchy expected by the api" do
    assert RecordingStudio.root_allowed?("Workspace")
    assert RecordingStudio.root_allowed?("Folder")
    refute RecordingStudio.root_allowed?("Page")
    refute RecordingStudio.root_allowed?("RecordingStudio::Access")
    refute RecordingStudio.root_allowed?("RecordingStudioApi::ApiClient")

    assert_equal %w[Workspace Folder], RecordingStudio.allowed_parent_types_for("Page")
    assert_equal %w[Workspace Folder], RecordingStudio.allowed_parent_types_for("Folder")
    assert_includes RecordingStudio.allowed_parent_types_for("RecordingStudio::Access"), "Workspace"
    assert_includes RecordingStudio.allowed_parent_types_for("RecordingStudio::Access"), "Folder"
    assert_includes RecordingStudio.allowed_parent_types_for("RecordingStudio::Access"), "AdminRoot"
    assert_equal ["RecordingStudio::Access"], RecordingStudio.allowed_parent_types_for("RecordingStudioApi::ApiClient")
    assert_equal ["RecordingStudioApi::ApiClient"], RecordingStudio.allowed_parent_types_for("RecordingStudioApi::ApiCredential")
    assert_equal ["RecordingStudioApi::ApiCredential"], RecordingStudio.allowed_parent_types_for("RecordingStudioApi::ApiAccessToken")
    assert_equal ["AdminRoot"], RecordingStudio.allowed_parent_types_for("RecordingStudioApi::AdminApi")
  end
end