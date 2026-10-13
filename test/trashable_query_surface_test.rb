# frozen_string_literal: true

require_relative "support/api_dummy_helpers"

# Proves query-only Trashable loading leaves the published dummy surface free of
# full-engine side effects (importmap pin/preload, capability, lifecycle methods,
# CopyHelper, trash metrics).
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

  test "query-only require leaves no Trashable engine side effects" do
    refute defined?(RecordingStudioTrashable::Engine), "Engine must stay unloaded"
    refute defined?(RecordingStudioTrashable::CopyHelper), "CopyHelper must stay unloaded"
    refute defined?(RecordingStudioTrashable::Metrics), "Trashable::Metrics must stay unloaded"

    refute RecordingStudio.registered_capabilities.key?(:trashable) if RecordingStudio.respond_to?(:registered_capabilities)

    recording = RecordingStudio::Recording.new
    refute_respond_to recording, :recording_studio_trashable_trash!
    refute_respond_to recording, :recording_studio_trashable_restore!
    refute_respond_to recording, :recording_studio_trashable_purge!

    importmap_paths = Array(Rails.application.config.importmap.paths).map(&:to_s)
    asset_paths = Array(Rails.application.config.assets.paths).map(&:to_s)
    refute(importmap_paths.any? { |path| path.include?("recording_studio_trashable") })
    refute(asset_paths.any? { |path| path.include?("recording_studio_trashable") })

    if defined?(RecordingStudioMetrics)
      refute RecordingStudioMetrics.find("trash.in_trash")
      refute RecordingStudioMetrics.find("trash.in_trash_by_type")
      refute RecordingStudioMetrics.find("trash.trashed_over_time")
    end

    importmap_json = Rails.application.importmap.to_json(resolver: ActionController::Base.helpers)
    refute_includes importmap_json, "controllers/recording_studio_trashable"
    refute_includes importmap_json, "live_search_controller"

    get "/users/sign_in"
    assert_response :success
    body = response.body
    refute_includes body, "controllers/recording_studio_trashable"
    refute_includes body, "live_search_controller"
    refute_match(/rel="modulepreload"[^>]+recording_studio_trashable/, body)

    loaded = $LOADED_FEATURES.map { |path| path.tr("\\", "/") }
    refute(loaded.any? { |path| path.end_with?("/recording_studio_trashable/engine.rb") })
    refute(loaded.any? { |path| path.end_with?("/lib/recording_studio_trashable.rb") })
    assert(loaded.any? { |path| path.end_with?("/recording_studio_trashable/query.rb") })
  end
end
