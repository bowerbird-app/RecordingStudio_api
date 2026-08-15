# frozen_string_literal: true

require_relative "hooks"
require_relative "action_registry"
require_relative "api_version_profile"
require_relative "recordable_registry"
require_relative "api_definition"

module RecordingStudioApi
  class Configuration
    DEFAULT_API_VERSION = "v1"

    ACCESS_ROLE_RANKS = {
      view: 0,
      edit: 1,
      admin: 2
    }.freeze

    attr_accessor :timeout,
                  :credential_ttl,
                  :access_token_ttl,
                  :token_authenticators,
                  :access_management_view_role,
                  :access_management_edit_role,
                  :api_management_authorization_required,
                  :token_digest_pepper,
                  :token_digest_legacy_verify,
                  :capability_action_role_resolver,
                  :admin_dashboard_path_resolver,
                  :admin_settings_path_resolver,
                  :admin_rate_limiting_path_resolver,
                  :admin_requests_path_resolver,
                  :admin_errors_path_resolver,
                  :admin_logs_path_resolver,
                  :admin_layout_name,
                  :admin_root_recordable_type_names,
                  :openapi_title,
                  :openapi_description,
                  :documentation_enabled,
                  :documentation_access,
                  :documentation_layout_name,
                  :layout_name,
                  :pagination_default_limit,
                  :pagination_max_limit,
                  :rate_limit_oauth_enabled,
                  :rate_limit_api_enabled,
                  :rate_limit_api_pre_auth_enabled,
                  :rate_limit_fail_closed,
                  :rate_limit_fail_closed_buckets,
                  :rate_limit_redis_url,
                  :rate_limit_redis_namespace,
                  :rate_limit_oauth_requests,
                  :rate_limit_oauth_period_seconds,
                  :rate_limit_api_pre_auth_requests,
                  :rate_limit_api_pre_auth_period_seconds,
                  :rate_limit_api_requests,
                  :rate_limit_api_period_seconds,
                  :rate_limit_api_read_requests,
                  :rate_limit_api_read_period_seconds,
                  :rate_limit_api_write_requests,
                  :rate_limit_api_write_period_seconds,
                  :api_request_logging_enabled,
                  :api_request_logging_payload_mode,
                  :api_request_logging_delivery,
                  :api_request_logging_batch_size,
                  :api_request_log_allowed_param_keys,
                  :api_request_log_retention_days,
                  :api_daily_metric_retention_days
    attr_reader :hooks, :action_registry, :recordable_registry, :default_api_version, :api_version_profiles, :capability_action_roles

    # rubocop:disable Metrics/AbcSize
    def initialize
      @timeout = 5
      @credential_ttl = 30.respond_to?(:days) ? 30.days : 30 * 24 * 60 * 60
      @access_token_ttl = 1.respond_to?(:hour) ? 1.hour : 60 * 60
      @token_authenticators = []
      @access_management_view_role = :view
      @access_management_edit_role = :admin
      @api_management_authorization_required = true
      @token_digest_pepper = ENV["RECORDING_STUDIO_API_TOKEN_DIGEST_PEPPER"].presence
      @token_digest_legacy_verify = true
      @capability_action_roles = {}
      @capability_action_role_resolver = nil
      @admin_dashboard_path_resolver = lambda do |controller:, **|
        controller.recording_studio_api.admin_dashboard_path
      end
      @admin_settings_path_resolver = lambda do |controller:, **params|
        controller.recording_studio_api.admin_settings_path(params)
      end
      @admin_rate_limiting_path_resolver = lambda do |controller:, **params|
        controller.recording_studio_api.admin_rate_limiting_path(params)
      end
      @admin_requests_path_resolver = lambda do |controller:, **params|
        controller.recording_studio_api.admin_requests_path(params)
      end
      @admin_errors_path_resolver = lambda do |controller:, **params|
        controller.recording_studio_api.admin_errors_path(params)
      end
      @admin_logs_path_resolver = lambda do |controller:, **params|
        controller.recording_studio_api.admin_logs_path(params)
      end
      @admin_layout_name = nil
      @admin_root_recordable_type_names = ["AdminRoot"]
      @api_versions = [DEFAULT_API_VERSION]
      @default_api_version = DEFAULT_API_VERSION
      @api_version_profiles = {}
      @openapi_title = nil
      @openapi_description = nil
      @documentation_enabled = false
      @documentation_access = nil
      @documentation_layout_name = nil
      @layout_name = "recording_studio/default_layout"
      @pagination_default_limit = 50
      @pagination_max_limit = 100
      @rate_limit_oauth_enabled = true
      @rate_limit_api_enabled = false
      @rate_limit_api_pre_auth_enabled = true
      @rate_limit_fail_closed = true
      @rate_limit_fail_closed_buckets = %w[oauth api_pre_auth]
      @rate_limit_redis_url = ENV["RECORDING_STUDIO_API_RATE_LIMIT_REDIS_URL"].presence
      @rate_limit_redis_namespace = "recording_studio_api"
      @rate_limit_oauth_requests = 10
      @rate_limit_oauth_period_seconds = 60
      @rate_limit_api_pre_auth_requests = 300
      @rate_limit_api_pre_auth_period_seconds = 60
      @rate_limit_api_requests = 120
      @rate_limit_api_period_seconds = 60
      @rate_limit_api_read_requests = 120
      @rate_limit_api_read_period_seconds = 60
      @rate_limit_api_write_requests = 30
      @rate_limit_api_write_period_seconds = 60
      @api_request_logging_enabled = false
      @api_request_logging_payload_mode = "metadata_only"
      @api_request_logging_delivery = "sync"
      @api_request_logging_batch_size = 25
      @api_request_log_allowed_param_keys = []
      @api_request_log_retention_days = 30
      @api_daily_metric_retention_days = nil
      @hooks = Hooks.new
      @action_registry = ActionRegistry.new
      @recordable_registry = RecordableRegistry.new
      @apis = {}
    end
    # rubocop:enable Metrics/AbcSize

    # rubocop:disable Metrics/AbcSize
    def to_h
      {
        timeout: timeout,
        credential_ttl: credential_ttl,
        access_token_ttl: access_token_ttl,
        api_management_authorization_required: api_management_authorization_required,
        token_digest_pepper_present: token_digest_pepper.present?,
        token_digest_legacy_verify: token_digest_legacy_verify,
        token_authenticators_count: token_authenticators.count,
        capability_action_roles: capability_action_roles,
        capability_action_role_resolver: capability_action_role_resolver.respond_to?(:call),
        admin_dashboard_path_resolver: admin_dashboard_path_resolver.respond_to?(:call),
        admin_settings_path_resolver: admin_settings_path_resolver.respond_to?(:call),
        admin_rate_limiting_path_resolver: admin_rate_limiting_path_resolver.respond_to?(:call),
        admin_requests_path_resolver: admin_requests_path_resolver.respond_to?(:call),
        admin_errors_path_resolver: admin_errors_path_resolver.respond_to?(:call),
        admin_logs_path_resolver: admin_logs_path_resolver.respond_to?(:call),
        admin_layout_name: admin_layout_name,
        admin_root_recordable_type_names: admin_root_recordable_type_names,
        api_versions: api_versions,
        default_api_version: default_api_version,
        api_version_profiles: api_version_profiles.transform_values(&:as_json),
        apis: @apis.transform_values(&:to_h),
        openapi_title: openapi_title,
        openapi_description: openapi_description,
        documentation_enabled: documentation_enabled,
        documentation_access: documentation_access.respond_to?(:call) ? :callable : documentation_access,
        documentation_layout_name: documentation_layout_name,
        layout_name: layout_name,
        pagination_default_limit: pagination_default_limit,
        pagination_max_limit: pagination_max_limit,
        rate_limit_oauth_enabled: rate_limit_oauth_enabled,
        rate_limit_api_enabled: rate_limit_api_enabled,
        rate_limit_api_pre_auth_enabled: rate_limit_api_pre_auth_enabled,
        rate_limit_fail_closed: rate_limit_fail_closed,
        rate_limit_fail_closed_buckets: rate_limit_fail_closed_buckets,
        rate_limit_redis_url_present: rate_limit_redis_url.present?,
        rate_limit_redis_namespace: rate_limit_redis_namespace,
        rate_limit_oauth_requests: rate_limit_oauth_requests,
        rate_limit_oauth_period_seconds: rate_limit_oauth_period_seconds,
        rate_limit_api_pre_auth_requests: rate_limit_api_pre_auth_requests,
        rate_limit_api_pre_auth_period_seconds: rate_limit_api_pre_auth_period_seconds,
        rate_limit_api_requests: rate_limit_api_requests,
        rate_limit_api_period_seconds: rate_limit_api_period_seconds,
        rate_limit_api_read_requests: rate_limit_api_read_requests,
        rate_limit_api_read_period_seconds: rate_limit_api_read_period_seconds,
        rate_limit_api_write_requests: rate_limit_api_write_requests,
        rate_limit_api_write_period_seconds: rate_limit_api_write_period_seconds,
        api_request_logging_enabled: api_request_logging_enabled,
        api_request_logging_payload_mode: api_request_logging_payload_mode,
        api_request_logging_delivery: api_request_logging_delivery,
        api_request_logging_batch_size: api_request_logging_batch_size,
        api_request_log_allowed_param_keys: api_request_log_allowed_param_keys,
        api_request_log_retention_days: api_request_log_retention_days,
        api_daily_metric_retention_days: api_daily_metric_retention_days,
        action_registrations: action_registry.to_h,
        recordable_registrations: recordable_registry.to_h,
        hooks_registered: hooks.instance_variable_get(:@registry).transform_values(&:size)
      }
    end
    # rubocop:enable Metrics/AbcSize

    def merge!(hash)
      return unless hash.respond_to?(:each)

      hash.each do |k, v|
        key = k.to_s
        setter = "#{key}="
        public_send(setter, v) if respond_to?(setter)
      end
    end

    def name
      "public"
    end

    def public_api
      self
    end

    def api(name = :public)
      normalized_name = normalize_api_name(name)
      definition = normalized_name == "public" ? public_api : (@apis[normalized_name] ||= ApiDefinition.new(normalized_name, defaults: public_api))
      yield(definition) if block_given?
      definition
    end

    def fetch_api(name = :public)
      normalized_name = normalize_api_name(name)
      return public_api if normalized_name == "public"

      @apis.fetch(normalized_name) do
        raise ConfigurationError, "Unknown API: #{normalized_name}"
      end
    end

    def api_names
      ["public", *@apis.keys]
    end

    def canonical_api_name(value)
      normalize_api_name(value)
    end

    def each_api(&block)
      return enum_for(:each_api) unless block_given?

      block.call(public_api)
      @apis.each_value(&block)
    end

    def []=(key, value)
      setter = "#{key}="
      public_send(setter, value) if respond_to?(setter)
    end

    def validate!
      action_registry.validate!
      recordable_registry.validate!
      @apis.each_value(&:validate!)
      validate_access_management_roles!
      validate_capability_action_role_resolver!
      validate_api_versions!
      validate_documentation!
      validate_security_configuration!
    end

    def api_versions
      (Array(@api_versions) + api_version_profiles.keys).filter_map { |entry| normalize_api_version(entry) }.uniq
    end

    def access_management_view_role=(value)
      @access_management_view_role = normalize_access_role(value, default: :view)
    end

    def access_management_edit_role=(value)
      @access_management_edit_role = normalize_access_role(value, default: :admin)
    end

    def capability_action_roles=(value)
      raise ConfigurationError, "capability_action_roles must be a hash" unless value.respond_to?(:each_pair)

      @capability_action_roles = value.each_pair.with_object({}) do |(action_name, role), roles|
        normalized_action_name = action_name.to_s.strip
        raise ConfigurationError, "capability action name is required" if normalized_action_name.empty?

        normalized_role = normalize_access_role(role, default: :edit)
        validate_access_role!(:capability_action_roles, normalized_role)
        roles[normalized_action_name] = normalized_role
      end
    end

    def capability_action_role_for(action:, recording:, api_client:, access_grant:)
      default_role = capability_action_roles.fetch(action.name, action.required_role)
      return default_role unless capability_action_role_resolver.respond_to?(:call)

      resolved_role = capability_action_role_resolver.call(
        action: action,
        recording: recording,
        api_client: api_client,
        access_grant: access_grant,
        default_role: default_role
      )
      normalized_role = normalize_access_role(resolved_role, default: default_role)
      validate_access_role!(:capability_action_role_resolver, normalized_role)
      normalized_role
    end

    def api_versions=(value)
      normalized_versions = Array(value).filter_map { |entry| normalize_api_version(entry) }.uniq
      @api_versions = normalized_versions.presence || [DEFAULT_API_VERSION]

      @default_api_version = @api_versions.first if @default_api_version.blank? || !@api_versions.include?(@default_api_version)
    end

    def default_api_version=(value)
      @default_api_version = normalize_api_version(value) || DEFAULT_API_VERSION
      @api_versions = Array(@api_versions).filter_map { |entry| normalize_api_version(entry) }.uniq
      @api_versions << @default_api_version unless @api_versions.include?(@default_api_version)
    end

    def version(value)
      normalized_version = normalize_api_version(value)
      raise ConfigurationError, "API version name is required" if normalized_version.blank?

      @api_versions = (Array(@api_versions) + [normalized_version]).uniq
      profile = (@api_version_profiles[normalized_version] ||= ApiVersionProfile.new(normalized_version))
      yield(profile) if block_given?
      profile
    end

    def api_version_profile_for(value)
      api_version_profiles[normalize_api_version(value)]
    end

    def []=(key, value)
      setter = "#{key}="
      public_send(setter, value) if respond_to?(setter)
    end

    private

    def validate_documentation!
      return unless documentation_enabled
      return if %i[public authenticated].include?(documentation_access) || documentation_access.respond_to?(:call)

      raise ConfigurationError, "documentation_access must be public, authenticated, or callable when documentation is enabled"
    end

    def normalize_api_name(value)
      raw_name = value.to_s.strip
      raise ConfigurationError, "API name may contain only letters, numbers, spaces, underscores, and hyphens" unless raw_name.match?(/\A[a-zA-Z0-9 _-]+\z/)

      normalized_name = raw_name.downcase.tr(" -", "__").gsub(/_+/, "_").delete_prefix("_").delete_suffix("_")
      raise ConfigurationError, "API name is required" if normalized_name.blank?

      normalized_name
    end

    def normalize_access_role(value, default:)
      normalized = value.to_s.strip
      normalized = default.to_s if normalized.blank?
      normalized.to_sym
    end

    def normalize_api_version(value)
      normalized = value.to_s.strip.downcase
      return if normalized.blank?

      normalized.start_with?("v") ? normalized : "v#{normalized}"
    end

    def validate_access_management_roles!
      validate_access_role!(:access_management_view_role, access_management_view_role)
      validate_access_role!(:access_management_edit_role, access_management_edit_role)

      return unless access_role_rank(access_management_view_role) > access_role_rank(access_management_edit_role)

      raise ConfigurationError, "Access management view role must be less than or equal to edit role"
    end

    def validate_capability_action_role_resolver!
      return if capability_action_role_resolver.nil? || capability_action_role_resolver.respond_to?(:call)

      raise ConfigurationError, "capability_action_role_resolver must respond to call"
    end

    def validate_access_role!(name, role)
      return if access_role_rank(role).present?

      raise ConfigurationError, "#{name} must be one of: #{valid_access_roles.join(', ')}"
    end

    def access_role_rank(role)
      ACCESS_ROLE_RANKS[role.to_sym]
    end

    def valid_access_roles
      ACCESS_ROLE_RANKS.keys
    end

    def validate_api_versions!
      return if api_versions.include?(default_api_version)

      raise ConfigurationError, "default_api_version must be included in api_versions"
    end

    def validate_security_configuration!
      validate_positive_duration!(:access_token_ttl, access_token_ttl)
      validate_non_negative_duration!(:credential_ttl, credential_ttl) if credential_ttl.present?
      validate_enabled_rate_limits!
      validate_positive_days!(:api_request_log_retention_days, api_request_log_retention_days)
      validate_positive_days!(:api_daily_metric_retention_days, api_daily_metric_retention_days) if api_daily_metric_retention_days.present?
      validate_api_request_logging_delivery!
    end

    def validate_api_request_logging_delivery!
      allowed = %w[sync async batched]
      return if allowed.include?(api_request_logging_delivery.to_s)

      raise ConfigurationError, "api_request_logging_delivery must be one of: #{allowed.join(', ')}"
    end

    def validate_enabled_rate_limits!
      validate_rate_limit!(:oauth, rate_limit_oauth_requests, rate_limit_oauth_period_seconds) if rate_limit_oauth_enabled
      validate_rate_limit!(:api_pre_auth, rate_limit_api_pre_auth_requests, rate_limit_api_pre_auth_period_seconds) if rate_limit_api_pre_auth_enabled
      return unless rate_limit_api_enabled

      validate_rate_limit!(:api_read, effective_rate_limit_value(rate_limit_api_read_requests, rate_limit_api_requests), effective_rate_limit_value(rate_limit_api_read_period_seconds, rate_limit_api_period_seconds))
      validate_rate_limit!(:api_write, effective_rate_limit_value(rate_limit_api_write_requests, rate_limit_api_requests), effective_rate_limit_value(rate_limit_api_write_period_seconds, rate_limit_api_period_seconds))
    end

    def effective_rate_limit_value(primary, fallback)
      primary.to_i.nonzero? || fallback
    end

    def validate_rate_limit!(bucket, requests, period)
      raise ConfigurationError, "rate_limit_#{bucket}_requests must be positive when rate limiting is enabled" unless positive_number?(requests)
      raise ConfigurationError, "rate_limit_#{bucket}_period_seconds must be positive when rate limiting is enabled" unless positive_number?(period)
    end

    def validate_positive_duration!(name, value)
      raise ConfigurationError, "#{name} must be positive" unless positive_number?(value)
    end

    def validate_non_negative_duration!(name, value)
      raise ConfigurationError, "#{name} must be non-negative" unless non_negative_number?(value)
    end

    def validate_positive_days!(name, value)
      raise ConfigurationError, "#{name} must be positive when configured" unless positive_number?(value)
    end

    def positive_number?(value)
      value.respond_to?(:to_i) && value.to_i.positive?
    end

    def non_negative_number?(value)
      value.respond_to?(:to_i) && value.to_i >= 0
    end
  end
end
