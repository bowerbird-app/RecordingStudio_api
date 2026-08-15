# frozen_string_literal: true

RecordingStudioApi.configure do |config|
  # Optional title shown in generated OpenAPI/Scalar docs.
  # Defaults to your Rails application module name (for example: Dummy).
  # config.openapi_title = "My App API"

  # Optional description shown in generated OpenAPI/Scalar docs.
  # Defaults to: "Add you API intro description in the config file"
  # config.openapi_description = "Endpoints for API access and resource operations"

  # Layout used by generated Scalar documentation and RecordingStudioApi engine pages.
  # config.layout_name = "recording_studio/default_layout"

  # Scalar documentation is disabled until explicitly enabled with an access policy.
  # config.documentation_enabled = true
  # config.documentation_access = :authenticated

  # Timeout in seconds for external calls
  # config.timeout = 5

  # Default lifetime for API credentials provisioned without an explicit expiry.
  config.credential_ttl = 30.days

  # OAuth bearer access tokens are short-lived because possession is authentication.
  config.access_token_ttl = 1.hour

  # Credential and access-token digests are HMAC-SHA256(pepper, token). Defaults to
  # Rails secret_key_base; override for dedicated rotation. Keep legacy SHA256 verify
  # enabled until existing credentials/tokens are rotated or rehashed.
  # config.token_digest_pepper = ENV.fetch("RECORDING_STUDIO_API_TOKEN_DIGEST_PEPPER", nil)
  # config.token_digest_legacy_verify = true

  # Require AdminApi management access when provisioning/managing credentials.
  # Disable only for intentionally open access-point delegation on an API.
  # config.api_management_authorization_required = true

  # Unauthenticated OAuth and API pre-auth buckets are rate-limited by default and
  # fail closed when Redis is unavailable. Authenticated API buckets remain opt-in.
  config.rate_limit_redis_url = ENV.fetch("RECORDING_STUDIO_API_RATE_LIMIT_REDIS_URL", nil)
  config.rate_limit_redis_namespace = "recording_studio_api"
  # config.rate_limit_oauth_enabled = true
  config.rate_limit_oauth_requests = 10
  config.rate_limit_oauth_period_seconds = 60
  # config.rate_limit_api_pre_auth_enabled = true
  config.rate_limit_api_pre_auth_requests = 120
  config.rate_limit_api_pre_auth_period_seconds = 60
  config.rate_limit_api_enabled = Rails.env.production?
  config.rate_limit_api_read_requests = 300
  config.rate_limit_api_read_period_seconds = 60
  config.rate_limit_api_write_requests = 60
  config.rate_limit_api_write_period_seconds = 60
  # config.rate_limit_fail_closed = true
  config.rate_limit_fail_closed_buckets = %w[oauth api_pre_auth]

  # Optional: log API requests to the API request log database
  # config.api_request_logging_enabled = true
  # Use "filtered_params" only when request parameter retention is required.
  # Only top-level keys in this allowlist are retained; Rails filter_parameters still applies.
  # config.api_request_log_allowed_param_keys = %w[grant_type resource sort order limit]
  # config.api_request_logging_payload_mode = "metadata_only"
  # Raw request details are retained for 30 days; daily aggregates are retained indefinitely.
  # config.api_request_log_retention_days = 30
  # config.api_daily_metric_retention_days = nil
end
