# frozen_string_literal: true

require_relative "../test_helper"
require "recording_studio_api/admin/api_request_log_helpers"

class ApiRequestLogHelpersTest < Minitest::Test
  def test_compact_path_removes_api_mount_prefix_and_replaces_uuid_segments
    path = "/recording_studio_api/api/v1/pages/ab5161c1-84dd-483c-9105-931e42ec93f7"

    assert_equal "/pages/:id", RecordingStudioApi::Admin::ApiRequestLogHelpers.compact_path(path)
  end

  def test_compact_path_replaces_numeric_segments_without_changing_named_segments
    path = "/recording_studio_api/api/v1/pages/27/actions/publish"

    assert_equal "/pages/:id/actions/publish", RecordingStudioApi::Admin::ApiRequestLogHelpers.compact_path(path)
  end

  def test_compact_path_preserves_non_api_paths_after_removing_engine_mount
    assert_equal "/oauth/token", RecordingStudioApi::Admin::ApiRequestLogHelpers.compact_path("/recording_studio_api/oauth/token")
    assert_equal "/", RecordingStudioApi::Admin::ApiRequestLogHelpers.compact_path("/recording_studio_api/api/v1")
  end
end