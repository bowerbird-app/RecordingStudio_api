# frozen_string_literal: true

require_relative "support/api_dummy_helpers"

# The dummy loads the Trashable engine, the same way it loads Accessible.
# Folder is trashable. Page is not.
class TrashableQuerySurfaceTest < ActionDispatch::IntegrationTest
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "dummy boot loads the Trashable engine and one trashable type" do
    assert defined?(RecordingStudioTrashable::Engine)
    assert defined?(RecordingStudioTrashable::CopyHelper)
    assert defined?(RecordingStudioTrashable::Metrics)
    assert RecordingStudio.registered_capabilities.key?(:trashable)

    recording = RecordingStudio::Recording.new
    assert_respond_to recording, :recording_studio_trashable_trash!
    assert_respond_to recording, :recording_studio_trashable_restore!
    assert_respond_to recording, :recording_studio_trashable_purge!
    assert RecordingStudio.capability_enabled?(:trashable, for: "Folder")
    refute RecordingStudio.capability_enabled?(:trashable, for: "Page")

    importmap_paths = Array(Rails.application.config.importmap.paths).map(&:to_s)
    asset_paths = Array(Rails.application.config.assets.paths).map(&:to_s)
    assert(importmap_paths.any? { |path| path.include?("RecordingStudio_trashable") && path.end_with?("/config/importmap.rb") })
    assert(asset_paths.any? { |path| path.include?("RecordingStudio_trashable") && path.end_with?("/app/javascript") })

    assert defined?(RecordingStudioMetrics)
    assert_equal :trash, RecordingStudioTrashable::Metrics::RESOURCE

    importmap_json = Rails.application.importmap.to_json(resolver: ActionController::Base.helpers)
    assert_includes importmap_json, "controllers/recording_studio_trashable"
    assert_includes importmap_json, "live_search_controller"

    get "/users/sign_in"
    assert_response :success
    body = response.body
    assert_includes body, "controllers/recording_studio_trashable"
    assert_includes body, "live_search_controller"

    loaded = $LOADED_FEATURES.map { |path| path.tr("\\", "/") }
    assert(loaded.any? { |path| path.end_with?("/recording_studio_trashable/engine.rb") })
    assert(loaded.any? { |path| path.end_with?("/lib/recording_studio_trashable.rb") })
    assert(loaded.any? { |path| path.end_with?("/recording_studio_trashable/query.rb") })
  end
end
