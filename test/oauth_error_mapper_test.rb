# frozen_string_literal: true

require_relative "test_helper"

class OauthErrorMapperTest < ActiveSupport::TestCase
  test "normalizes non-hash errors into a generic server error payload" do
    payload = RecordingStudioApi::OauthErrorMapper.payload_for("database constraint detail")

    assert_equal "server_error", payload.fetch(:error)
    assert_equal RecordingStudioApi::OauthErrorMapper::SERVER_ERROR_DESCRIPTION, payload.fetch(:error_description)
    assert_not_includes payload.fetch(:error_description), "database constraint detail"
  end

  test "preserves hash error payloads" do
    payload = RecordingStudioApi::OauthErrorMapper.payload_for(error: "invalid_grant", error_description: "bad code")

    assert_equal "invalid_grant", payload.fetch(:error)
    assert_equal "bad code", payload.fetch(:error_description)
  end

  test "maps invalid_client to unauthorized" do
    status = RecordingStudioApi::OauthErrorMapper.status_for(error: "invalid_client")

    assert_equal :unauthorized, status
  end

  test "maps access_denied to forbidden" do
    status = RecordingStudioApi::OauthErrorMapper.status_for(error: "access_denied")

    assert_equal :forbidden, status
  end

  test "maps unsupported_grant_type to bad request" do
    status = RecordingStudioApi::OauthErrorMapper.status_for(error: "unsupported_grant_type")

    assert_equal :bad_request, status
  end
end