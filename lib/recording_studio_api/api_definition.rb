# frozen_string_literal: true

require_relative "action_registry"
require_relative "api_version_profile"
require_relative "recordable_registry"

module RecordingStudioApi
  class ApiDefinition
    DEFAULT_API_VERSION = "v1"

    attr_accessor :mount_path,
                  :openapi_title,
                  :openapi_description,
                  :authentication,
                  :default_access,
                  :documentation_enabled,
                  :documentation_access,
                  :documentation_layout_name,
                  :api_management_authorization_required,
                  :credential_ttl,
                  :access_token_ttl,
                  :rate_limit_oauth_enabled,
                  :rate_limit_api_enabled,
                  :rate_limit_api_pre_auth_enabled,
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
                  :api_request_log_allowed_param_keys
    attr_reader :name, :action_registry, :recordable_registry, :default_api_version, :api_version_profiles

    def initialize(name, defaults: nil)
      @name = name.to_s.freeze
      @mount_path = "/apis/#{@name}"
      @openapi_title = nil
      @openapi_description = nil
      @authentication = :oauth
      @default_access = :read_write
      @documentation_enabled = false
      @documentation_access = nil
      @documentation_layout_name = nil
      inherit_policy_defaults(defaults)
      @api_versions = [DEFAULT_API_VERSION]
      @default_api_version = DEFAULT_API_VERSION
      @api_version_profiles = {}
      @action_registry = ActionRegistry.new
      @recordable_registry = RecordableRegistry.new
    end

    def api_versions
      (Array(@api_versions) + api_version_profiles.keys).filter_map { |entry| normalize_api_version(entry) }.uniq
    end

    def api_versions=(value)
      normalized_versions = Array(value).filter_map { |entry| normalize_api_version(entry) }.uniq
      @api_versions = normalized_versions.presence || [DEFAULT_API_VERSION]
      self.default_api_version = @api_versions.first unless @api_versions.include?(@default_api_version)
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

    def validate!
      action_registry.validate!
      recordable_registry.validate!
      raise ConfigurationError, "authentication must be oauth for #{name}" unless authentication == :oauth
      raise ConfigurationError, "default_access must be read_only or read_write for #{name}" unless %i[read_only read_write].include?(default_access)

      validate_documentation!
      return if api_versions.include?(default_api_version)

      raise ConfigurationError, "default_api_version must be included in api_versions for #{name}"
    end

    def to_h
      {
        name: name,
        mount_path: mount_path,
        api_versions: api_versions,
        default_api_version: default_api_version,
        api_version_profiles: api_version_profiles.transform_values(&:as_json),
        openapi_title: openapi_title,
        openapi_description: openapi_description,
        authentication: authentication,
        default_access: default_access,
        documentation_enabled: documentation_enabled,
        documentation_access: documentation_access.respond_to?(:call) ? :callable : documentation_access,
        documentation_layout_name: documentation_layout_name,
        api_management_authorization_required: api_management_authorization_required,
        credential_ttl: credential_ttl,
        access_token_ttl: access_token_ttl,
        action_registrations: action_registry.to_h,
        recordable_registrations: recordable_registry.to_h
      }
    end

    private

    def validate_documentation!
      return unless documentation_enabled
      return if %i[public authenticated].include?(documentation_access) || documentation_access.respond_to?(:call)

      raise ConfigurationError, "documentation_access must be public, authenticated, or callable for #{name} when documentation is enabled"
    end

    def inherit_policy_defaults(defaults)
      policy_attributes = %i[
        api_management_authorization_required
        credential_ttl access_token_ttl
        rate_limit_oauth_enabled rate_limit_api_enabled rate_limit_api_pre_auth_enabled
        rate_limit_oauth_requests rate_limit_oauth_period_seconds
        rate_limit_api_pre_auth_requests rate_limit_api_pre_auth_period_seconds
        rate_limit_api_requests rate_limit_api_period_seconds
        rate_limit_api_read_requests rate_limit_api_read_period_seconds
        rate_limit_api_write_requests rate_limit_api_write_period_seconds
        api_request_logging_enabled api_request_logging_payload_mode api_request_log_allowed_param_keys
      ]
      policy_attributes.each do |attribute|
        value = defaults&.public_send(attribute)
        value = value.dup if value.respond_to?(:dup) && !value.is_a?(Numeric)
        instance_variable_set("@#{attribute}", value)
      end
    end

    def normalize_api_version(value)
      normalized = value.to_s.strip.downcase
      return if normalized.blank?

      normalized.start_with?("v") ? normalized : "v#{normalized}"
    end
  end
end