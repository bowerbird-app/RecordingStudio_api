# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"
require "devise/test/integration_helpers"
require "base64"

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

  test "ignores client credentials supplied only in the query string" do
    query = {
      grant_type: "client_credentials",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: @payload.fetch(:token)
    }.to_query

    post "/recording_studio_api/oauth/token?#{query}"

    assert_response :bad_request
    body = JSON.parse(response.body)
    assert_equal "invalid_request", body.fetch("error")
    assert_equal "grant_type is required", body.fetch("error_description")
  end

  test "does not accept client_secret from the query string when body omits it" do
    post "/recording_studio_api/oauth/token?client_secret=#{CGI.escape(@payload.fetch(:token))}",
         params: {
           grant_type: "client_credentials",
           client_id: @payload.fetch(:credential).oauth_client_id
         }

    assert_response :bad_request
    body = JSON.parse(response.body)
    assert_equal "invalid_request", body.fetch("error")
    assert_equal "client_secret is required", body.fetch("error_description")
  end

  test "returns oauth error for invalid client credentials" do
    post "/recording_studio_api/oauth/token", params: {
      grant_type: "client_credentials",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: "invalid"
    }

    assert_response :unauthorized
    assert_equal 'Basic realm="RecordingStudioApi"', response.headers["WWW-Authenticate"]
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_includes response.headers["Cache-Control"], "private"
    assert_equal "no-cache", response.headers["Pragma"]
    assert_equal "0", response.headers["Expires"]
    body = JSON.parse(response.body)
    assert_equal "invalid_client", body.fetch("error")
  end

  test "returns WWW-Authenticate for unknown client_id" do
    post "/recording_studio_api/oauth/token", params: {
      grant_type: "client_credentials",
      client_id: "missing-client-id",
      client_secret: "not-a-real-secret"
    }

    assert_response :unauthorized
    assert_equal 'Basic realm="RecordingStudioApi"', response.headers["WWW-Authenticate"]
    body = JSON.parse(response.body)
    assert_equal "invalid_client", body.fetch("error")
    assert_equal "client authentication failed", body.fetch("error_description")
  end

  test "rejects unknown grant types as invalid_grant" do
    post "/recording_studio_api/oauth/token", params: {
      grant_type: "custom_grant",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: @payload.fetch(:token)
    }

    assert_response :bad_request
    assert_nil response.headers["WWW-Authenticate"]
    body = JSON.parse(response.body)
    assert_equal "invalid_grant", body.fetch("error")
  end

  test "rejects authorization_code when no grant handler is registered" do
    post "/recording_studio_api/oauth/token", params: {
      grant_type: "authorization_code",
      code: "abc",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: @payload.fetch(:token)
    }

    assert_response :bad_request
    body = JSON.parse(response.body)
    assert_equal "invalid_grant", body.fetch("error")
  end

  test "exchanges a registered grant type on the public token endpoint" do
    RecordingStudioApi.register_oauth_grant(
      "authorization_code",
      handler: lambda do |**kwargs|
        RecordingStudioApi::Services::BaseService::Result.new(
          success: true,
          value: {
            access_token: "rsapi_at_double",
            token_type: "Bearer",
            expires_in: 3600,
            grant_api: kwargs.fetch(:api),
            code: kwargs.fetch(:params)["code"]
          }
        )
      end
    )

    post "/recording_studio_api/oauth/token", params: {
      grant_type: "authorization_code",
      code: "abc",
      client_id: "oauth-client",
      client_secret: "oauth-secret"
    }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "rsapi_at_double", body.fetch("access_token")
    assert_equal "Bearer", body.fetch("token_type")
    assert_equal "public", body.fetch("grant_api")
    assert_equal "abc", body.fetch("code")
  end

  test "exchanges a registered grant type on a named api token endpoint" do
    RecordingStudioApi.configuration.api(:operations)
    RecordingStudioApi.register_oauth_grant(
      "refresh_token",
      handler: lambda do |**kwargs|
        RecordingStudioApi::Services::BaseService::Result.new(
          success: true,
          value: {
            access_token: "rsapi_at_refresh",
            token_type: "Bearer",
            expires_in: 3600,
            grant_api: kwargs.fetch(:api)
          }
        )
      end
    )

    post "/recording_studio_api/apis/operations/oauth/token", params: {
      grant_type: "refresh_token",
      refresh_token: "rt-1"
    }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "rsapi_at_refresh", body.fetch("access_token")
    assert_equal "operations", body.fetch("grant_api")
  end

  test "still issues client_credentials after another grant is registered" do
    RecordingStudioApi.register_oauth_grant(
      "authorization_code",
      handler: lambda do |**|
        RecordingStudioApi::Services::BaseService::Result.new(
          success: true,
          value: { access_token: "rsapi_at_double", token_type: "Bearer", expires_in: 3600 }
        )
      end
    )

    post "/recording_studio_api/oauth/token", params: {
      grant_type: "client_credentials",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: @payload.fetch(:token)
    }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "Bearer", body.fetch("token_type")
    assert_match(/\Arsapi_at_/, body.fetch("access_token"))
    refute_equal "rsapi_at_double", body.fetch("access_token")
  end

  test "accepts HTTP Basic client credentials for token issuance" do
    credentials = Base64.strict_encode64(
      "#{@payload.fetch(:credential).oauth_client_id}:#{@payload.fetch(:token)}"
    )

    post "/recording_studio_api/oauth/token",
         params: { grant_type: "client_credentials" },
         headers: { "Authorization" => "Basic #{credentials}" }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "Bearer", body.fetch("token_type")
    assert_match(/\Arsapi_at_/, body.fetch("access_token"))
  end

  test "prefers body client credentials over HTTP Basic" do
    other_credentials = Base64.strict_encode64("wrong-id:wrong-secret")

    post "/recording_studio_api/oauth/token",
         params: {
           grant_type: "client_credentials",
           client_id: @payload.fetch(:credential).oauth_client_id,
           client_secret: @payload.fetch(:token)
         },
         headers: { "Authorization" => "Basic #{other_credentials}" }

    assert_response :success
  end

  test "revokes an issued access token" do
    post "/recording_studio_api/oauth/token", params: {
      grant_type: "client_credentials",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: @payload.fetch(:token)
    }
    assert_response :success
    access_token = JSON.parse(response.body).fetch("access_token")

    post "/recording_studio_api/oauth/revoke", params: {
      token: access_token,
      token_type_hint: "access_token",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: @payload.fetch(:token)
    }

    assert_response :success
    assert_equal "", response.body
    assert_includes response.headers["Cache-Control"], "no-store"

    token_record = RecordingStudioApi::ApiAccessToken.find_by!(
      token_digest: RecordingStudioApi::OauthAccessToken.digest(access_token)
    )
    assert_not_nil token_record.revoked_at

    get "/recording_studio_api/api/v1/pages",
        headers: { "Authorization" => "Bearer #{access_token}" }
    assert_response :unauthorized
  end

  test "revoke returns success for unknown tokens after client authentication" do
    post "/recording_studio_api/oauth/revoke", params: {
      token: "rsapi_at_unknown-token-value",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: @payload.fetch(:token)
    }

    assert_response :success
  end

  test "revoke rejects invalid client credentials" do
    post "/recording_studio_api/oauth/revoke", params: {
      token: "rsapi_at_anything",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: "bad-secret"
    }

    assert_response :unauthorized
    assert_equal 'Basic realm="RecordingStudioApi"', response.headers["WWW-Authenticate"]
    assert_equal "invalid_client", JSON.parse(response.body).fetch("error")
  end
end
