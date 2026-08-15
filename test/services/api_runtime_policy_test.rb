# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "../test_helper"
require_relative "../dummy/config/environment"

class ApiRuntimePolicyTest < ActiveSupport::TestCase
  setup do
    RecordingStudioApi::ApiSetting.where("key LIKE ?", "api%").delete_all
    @original_logging = RecordingStudioApi.configuration.api_request_logging_enabled
    @original_api_rl = RecordingStudioApi.configuration.rate_limit_api_enabled
    @original_credential_ttl = RecordingStudioApi.configuration.credential_ttl
    @original_retention = RecordingStudioApi.configuration.api_request_log_retention_days
    RecordingStudioApi.configuration.api_request_logging_enabled = false
    RecordingStudioApi.configuration.rate_limit_api_enabled = false
    RecordingStudioApi.configuration.credential_ttl = 30.days
    RecordingStudioApi.configuration.api_request_log_retention_days = 30
  end

  teardown do
    RecordingStudioApi::ApiSetting.where("key LIKE ?", "api%").delete_all
    RecordingStudioApi.configuration.api_request_logging_enabled = @original_logging
    RecordingStudioApi.configuration.rate_limit_api_enabled = @original_api_rl
    RecordingStudioApi.configuration.credential_ttl = @original_credential_ttl
    RecordingStudioApi.configuration.api_request_log_retention_days = @original_retention
  end

  test "falls back to initializer defaults when no overrides exist" do
    policy = RecordingStudioApi::ApiRuntimePolicy.for(:public)

    refute policy.api_request_logging_enabled
    refute policy.rate_limit_api_enabled
    assert_equal 30.days.to_i, policy.credential_ttl.to_i
    assert_equal 30, policy.api_request_log_retention_days
  end

  test "applies per-api overrides over initializer defaults" do
    RecordingStudioApi::ApiSetting.for_api(:public).apply_runtime_overrides!(
      "api_request_logging_enabled" => true,
      "rate_limit_api_enabled" => true,
      "credential_ttl_seconds" => 3_600,
      "rate_limit_api_read_requests" => 25
    )

    policy = RecordingStudioApi::ApiRuntimePolicy.for(:public)

    assert policy.api_request_logging_enabled
    assert policy.rate_limit_api_enabled
    assert_equal 3_600, policy.credential_ttl.to_i
    assert_equal 25, policy.rate_limit_api_read_requests
  end

  test "blank override values clear back to config defaults" do
    setting = RecordingStudioApi::ApiSetting.for_api(:public)
    setting.apply_runtime_overrides!("api_request_logging_enabled" => true)
    setting.apply_runtime_overrides!("api_request_logging_enabled" => "")

    refute RecordingStudioApi::ApiRuntimePolicy.for(:public).api_request_logging_enabled
    refute setting.reload.runtime_overrides_hash.key?("api_request_logging_enabled")
  end

  test "retention overrides are global on the public settings row" do
    RecordingStudioApi.configuration.api(:operations)
    RecordingStudioApi::ApiSetting.for_api(:public).apply_runtime_overrides!(
      "api_request_log_retention_days" => 7,
      "api_daily_metric_retention_days" => "indefinite"
    )

    policy = RecordingStudioApi::ApiRuntimePolicy.for(:operations)
    assert_equal 7, policy.api_request_log_retention_days
    assert_nil policy.api_daily_metric_retention_days
  end
end
