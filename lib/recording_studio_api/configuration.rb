# frozen_string_literal: true

require_relative "hooks"
require_relative "action_registry"
require_relative "api_version_profile"
require_relative "recordable_registry"

module RecordingStudioApi
  class Configuration
    DEFAULT_API_VERSION = "v1"

    ACCESS_ROLE_RANKS = {
      view: 0,
      edit: 1,
      admin: 2
    }.freeze

    attr_accessor :timeout,
                  :token_ttl,
                  :token_authenticators,
                  :access_management_view_role,
                  :access_management_edit_role,
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
                  :layout_name,
                  :pagination_default_limit,
                  :pagination_max_limit,
                  :rate_limit_oauth_enabled,
                  :rate_limit_api_enabled,
                  :rate_limit_api_pre_auth_enabled,
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
                  :api_request_logging_payload_mode
    attr_reader :hooks, :action_registry, :recordable_registry, :default_api_version, :api_version_profiles

    # rubocop:disable Metrics/AbcSize
    def initialize
      @timeout = 5
      @token_ttl = 30.respond_to?(:days) ? 30.days : 30 * 24 * 60 * 60
      @token_authenticators = []
      @access_management_view_role = :view
      @access_management_edit_role = :admin
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
      @layout_name = "recording_studio/default_layout"
      @pagination_default_limit = 50
      @pagination_max_limit = 100
      @rate_limit_oauth_enabled = false
      @rate_limit_api_enabled = false
      @rate_limit_api_pre_auth_enabled = false
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
      @hooks = Hooks.new
      @action_registry = ActionRegistry.new
      @recordable_registry = RecordableRegistry.new
    end
    # rubocop:enable Metrics/AbcSize

    def to_h
      {
        timeout: timeout,
        token_ttl: token_ttl,
        token_authenticators_count: token_authenticators.count,
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
        openapi_title: openapi_title,
        openapi_description: openapi_description,
        layout_name: layout_name,
        pagination_default_limit: pagination_default_limit,
        pagination_max_limit: pagination_max_limit,
        rate_limit_oauth_enabled: rate_limit_oauth_enabled,
        rate_limit_api_enabled: rate_limit_api_enabled,
        rate_limit_api_pre_auth_enabled: rate_limit_api_pre_auth_enabled,
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
        action_registrations: action_registry.to_h,
        recordable_registrations: recordable_registry.to_h,
        hooks_registered: hooks.instance_variable_get(:@registry).transform_values(&:size)
      }
    end

    def merge!(hash)
      return unless hash.respond_to?(:each)

      hash.each do |k, v|
        key = k.to_s
        setter = "#{key}="
        public_send(setter, v) if respond_to?(setter)
      end
    end

    def []=(key, value)
      setter = "#{key}="
      public_send(setter, value) if respond_to?(setter)
    end

    def validate!
      action_registry.validate!
      recordable_registry.validate!
      validate_access_management_roles!
      validate_api_versions!
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
  end
end
