# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"
require "devise/test/integration_helpers"

class OauthControllerTest < ActionDispatch::IntegrationTest
  include ApiDummyHelpers
  include Devise::Test::IntegrationHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    _root_recording, @access_recording = create_access_recording_for(user: @user)
    sign_in @user
    @payload = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: @access_recording,
      name: "OAuth endpoint client"
    ).value
  end

  teardown do
    RecordingStudioApi::Concerns::RateLimiting.decider = nil
    RecordingStudioApi::Concerns::RequestLogging.writer = nil
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "returns too many requests when oauth endpoint is rate limited" do
    RecordingStudioApi.configuration.rate_limit_oauth_enabled = true
    RecordingStudioApi::Concerns::RateLimiting.decider = lambda {
      {
        limited: true,
        limit: 1,
        remaining: 0,
        retry_after: 42
      }
    }

    post "/recording_studio_api/oauth/token", params: {
      grant_type: "client_credentials",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: @payload.fetch(:token)
    }

    assert_response :too_many_requests
    assert_equal "42", response.headers["Retry-After"]
    assert_equal "1", response.headers["X-RateLimit-Limit"]
    assert_equal "0", response.headers["X-RateLimit-Remaining"]

    body = JSON.parse(response.body)
    assert_equal "rate_limit_exceeded", body.fetch("error")
  end

  test "rejects token issuance when API access is disabled" do
    RecordingStudioApi::ApiSetting.find_or_create_by!(key: "api")
                                  .update!(api_access_enabled: false)

    post "/recording_studio_api/oauth/token", params: {
      grant_type: "client_credentials",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: @payload.fetch(:token)
    }

    assert_response :service_unavailable
    assert_equal "api_access_disabled", JSON.parse(response.body).fetch("error")
  end

  test "fails closed when oauth rate limiter is unavailable" do
    RecordingStudioApi.configuration.rate_limit_oauth_enabled = true
    RecordingStudioApi.configuration.rate_limit_fail_closed = true
    RecordingStudioApi.configuration.rate_limit_fail_closed_buckets = %w[oauth api_pre_auth]
    RecordingStudioApi::Concerns::RateLimiting.decider = lambda do |_controller|
      raise "redis offline"
    end

    post "/recording_studio_api/oauth/token", params: {
      grant_type: "client_credentials",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: @payload.fetch(:token)
    }

    assert_response :too_many_requests
    assert_equal "60", response.headers["Retry-After"]
    body = JSON.parse(response.body)
    assert_equal "rate_limit_exceeded", body.fetch("error")
  end

  test "writes oauth request log metadata without params by default" do
    RecordingStudioApi.configuration.api_request_logging_enabled = true
    logged_payloads = []
    RecordingStudioApi::Concerns::RequestLogging.writer = lambda do |payload|
      logged_payloads << payload
    end

    post "/recording_studio_api/oauth/token", params: {
      grant_type: "client_credentials",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: "bad-secret"
    }

    assert_response :unauthorized
    assert_equal 1, logged_payloads.length

    payload = logged_payloads.first
    assert_equal "POST", payload.fetch(:request_method)
    assert_equal "/recording_studio_api/oauth/token", payload.fetch(:request_path)
    assert_equal 401, payload.fetch(:status_code)
    assert_equal({}, payload.fetch(:request_params))
  end

  test "retains no oauth request params without an allowlist" do
    RecordingStudioApi.configuration.api_request_logging_enabled = true
    RecordingStudioApi.configuration.api_request_logging_payload_mode = "filtered_params"
    logged_payloads = []
    RecordingStudioApi::Concerns::RequestLogging.writer = lambda do |payload|
      logged_payloads << payload
    end

    post "/recording_studio_api/oauth/token", params: {
      grant_type: "client_credentials",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: "bad-secret"
    }

    assert_response :unauthorized
    assert_equal({}, logged_payloads.first.fetch(:request_params))
  end

  test "recursively filters oauth request params when payload logging is enabled" do
    RecordingStudioApi.configuration.api_request_logging_enabled = true
    RecordingStudioApi.configuration.api_request_logging_payload_mode = "filtered_params"
    RecordingStudioApi.configuration.api_request_log_allowed_param_keys = %w[grant_type client_secret metadata]
    logged_payloads = []
    RecordingStudioApi::Concerns::RequestLogging.writer = lambda do |payload|
      logged_payloads << payload
    end

    post "/recording_studio_api/oauth/token", params: {
      grant_type: "client_credentials",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: "bad-secret",
      metadata: {
        label: "safe label",
        password: "nested-password",
        credentials: {
          refresh_token: "nested-refresh-token",
          client_secret: "nested-client-secret"
        }
      }
    }

    assert_response :unauthorized
    assert_equal 1, logged_payloads.length

    request_params = logged_payloads.first.fetch(:request_params)
    assert_equal "client_credentials", request_params.fetch("grant_type")
    assert_equal "safe label", request_params.fetch("metadata").fetch("label")
    assert_equal "[FILTERED]", request_params.fetch("client_secret")
    assert_equal "[FILTERED]", request_params.fetch("metadata").fetch("password")
    assert_equal "[FILTERED]", request_params.fetch("metadata").fetch("credentials").fetch("refresh_token")
    assert_equal "[FILTERED]", request_params.fetch("metadata").fetch("credentials").fetch("client_secret")
    assert_equal "[FILTERED]", request_params.fetch("client_secret")
    assert_not_includes request_params, "client_id"
  end

  test "named oauth route rejects credentials from another api" do
    RecordingStudioApi.configuration.api(:operations)

    post "/recording_studio_api/apis/operations/oauth/token", params: {
      grant_type: "client_credentials",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: @payload.fetch(:token)
    }

    assert_response :unauthorized
    assert_equal "invalid_client", JSON.parse(response.body).fetch("error")
  end

  test "issues access token with valid client credentials" do
    post "/recording_studio_api/oauth/token", params: {
      grant_type: "client_credentials",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: @payload.fetch(:token)
    }

    assert_response :success
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_includes response.headers["Cache-Control"], "private"
    assert_equal "no-cache", response.headers["Pragma"]
    assert_equal "0", response.headers["Expires"]
    body = JSON.parse(response.body)
    assert_equal "Bearer", body.fetch("token_type")
    assert_match(/\Arsapi_at_/, body.fetch("access_token"))
  end

  test "returns oauth error for invalid client credentials" do
    post "/recording_studio_api/oauth/token", params: {
      grant_type: "client_credentials",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: "invalid"
    }

    assert_response :unauthorized
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_includes response.headers["Cache-Control"], "private"
    assert_equal "no-cache", response.headers["Pragma"]
    assert_equal "0", response.headers["Expires"]
    body = JSON.parse(response.body)
    assert_equal "invalid_client", body.fetch("error")
  end

  test "falls back to client credentials flow for unsupported grant type" do
    post "/recording_studio_api/oauth/token", params: {
      grant_type: "custom_grant",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: @payload.fetch(:token)
    }

    assert_response :bad_request
    body = JSON.parse(response.body)
    assert_equal "unsupported_grant_type", body.fetch("error")
  end
end
