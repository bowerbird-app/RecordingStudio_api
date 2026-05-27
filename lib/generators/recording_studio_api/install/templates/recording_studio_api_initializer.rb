# frozen_string_literal: true

RecordingStudioApi.configure do |config|
  # Optional title shown in generated OpenAPI/Scalar docs.
  # Defaults to your Rails application module name (for example: Dummy).
  # config.openapi_title = "My App API"

  # Optional description shown in generated OpenAPI/Scalar docs.
  # Defaults to: "Add you API intro description in the config file"
  # config.openapi_description = "Endpoints for the Mobile App integration"

  # Timeout in seconds for external calls
  # config.timeout = 5

  # Default access token lifetime for OAuth2 client_credentials exchanges
  # config.token_ttl = 30.days

  # Optional Redis-backed rate limiting
  # config.rate_limit_oauth_enabled = true
  # config.rate_limit_redis_url = ENV["RECORDING_STUDIO_API_RATE_LIMIT_REDIS_URL"]
  # config.rate_limit_redis_namespace = "recording_studio_api"
  # config.rate_limit_oauth_requests = 10
  # config.rate_limit_oauth_period_seconds = 60
  # config.rate_limit_api_enabled = false
  # config.rate_limit_api_read_requests = 120
  # config.rate_limit_api_read_period_seconds = 60
  # config.rate_limit_api_write_requests = 30
  # config.rate_limit_api_write_period_seconds = 60

  # Optional: log API requests to the API request log database
  # config.api_request_logging_enabled = true
  # config.api_request_logging_payload_mode = "metadata_only"
end
