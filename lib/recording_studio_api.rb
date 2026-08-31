# frozen_string_literal: true

require "recording_studio_api/version"
require "recording_studio_accessible"
require "recording_studio_api/engine"
require "recording_studio_api/errors"
require "recording_studio_api/configuration"
require "recording_studio_api/scalar_asset"
require "recording_studio_api/routing"
require "recording_studio_api/authenticated_client"
require "recording_studio_api/access_grant"
require "recording_studio_api/integration"
require "recording_studio_api/action_context"
require "recording_studio_api/resource_operation_context"
require "recording_studio_api/accessible_recording_scope"
require "recording_studio_api/access_policy"
require "recording_studio_api/api_runtime_policy"
require "recording_studio_api/recordable_registry"
require "recording_studio_api/api_request_log_batch"
require "recording_studio_api/api_request_log_delivery"
require "recording_studio_api/token_digest"
require "recording_studio_api/token"
require "recording_studio_api/pkce"
require "recording_studio_api/authorization_code"
require "recording_studio_api/refresh_token"
require "recording_studio_api/oauth_client_secret"
require "recording_studio_api/oauth_access_token"
require "recording_studio_api/oauth_error_mapper"
require "recording_studio_api/delegated_oauth_voiding"
require "recording_studio_api/idempotency_store"
require "recording_studio_api/openapi_helpers"
require "recording_studio_api/relationship_batch_loader"
require "recording_studio_api/relationship_context"
require "recording_studio_api/serializer_context"
require "recording_studio_api/serializers/recording_serializer"
require "recording_studio_api/serializers/resource_recording_serializer"
require "recording_studio_api/services/base_service"
require "recording_studio_api/services/token_authentication_base"
require "recording_studio_api/access_management_policy"
require "recording_studio_api/api_client_management_policy"
require "recording_studio_api/services/provision_api_client"
require "recording_studio_api/services/provision_access_request"
require "recording_studio_api/services/rotate_api_credential"
require "recording_studio_api/services/authenticate_bearer_token"
require "recording_studio_api/services/issue_oauth_access_token"
require "recording_studio_api/services/resolve_oauth_client"
require "recording_studio_api/services/authenticate_oauth_client"
require "recording_studio_api/services/create_oauth_authorization"
require "recording_studio_api/services/void_oauth_authorization"
require "recording_studio_api/services/revoke_oauth_access_token"
require "recording_studio_api/services/authenticate_oauth_access_token"
require "recording_studio_api/services/issue_test_credential"
require "recording_studio_api/services/revoke_test_credential"
require "recording_studio_api/services/move_recording"
require "recording_studio_api/services/documentation_catalog"
require "recording_studio_api/services/openapi_document"
require "recording_studio_api/services/paginate_resource_collection"
require "recording_studio_api/services/aggregate_api_request_log_metrics"
require "recording_studio_api/services/prune_api_request_logs"
require "recording_studio_api/services/prune_api_daily_metrics"
require "recording_studio_api/services/maintain_api_metrics"
require "recording_studio_api/services/resource_operations/base"
require "recording_studio_api/services/resource_operations/index"
require "recording_studio_api/services/resource_operations/show"
require "recording_studio_api/services/resource_operations/create"
require "recording_studio_api/services/resource_operations/update"
require "recording_studio_api/services/resource_operations/destroy"
require "recording_studio_api/admin"

# rubocop:disable Metrics/ModuleLength
module RecordingStudioApi
  class << self
    include OpenapiHelpers

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
    end

    def api(name = :public)
      configuration.fetch_api(name)
    end

    def register_token_authenticator(authenticator = nil, &block)
      resolved = authenticator || block
      raise ArgumentError, "A callable authenticator is required" unless resolved.respond_to?(:call)

      configuration.token_authenticators << resolved
      resolved
    end

    def token_authenticators
      configuration.token_authenticators
    end

    def authenticate_authorization_header(authorization_header:, api: :public)
      Integration.authenticate_authorization_header(authorization_header: authorization_header, api: api)
    end

    def build_access_grant(authenticated_client:)
      Integration.build_access_grant(authenticated_client: authenticated_client)
    end

    def access_grant_from_authorization_header(authorization_header:, api: :public)
      Integration.access_grant_from_authorization_header(authorization_header: authorization_header, api: api)
    end

    def actor_access_recordings(actor:)
      Integration.actor_access_recordings(actor: actor)
    end

    def resolve_access_recording_for_actor(actor:, requested_access_recording_id: nil)
      Integration.resolve_access_recording_for_actor(
        actor: actor,
        requested_access_recording_id: requested_access_recording_id
      )
    end

    def oauth_error_payload(error)
      Integration.oauth_error_payload(error)
    end

    def oauth_error_status(error)
      Integration.oauth_error_status(error)
    end

    def register_capability_action(name, capability:, version: nil, version_notes: nil, deprecation: nil, http_verb: :post, handler:, serializer: nil, scope: :member, openapi: nil, input_contract: nil, required_role: nil, api: :public)
      configuration.api(api).action_registry.register(
        name,
        capability: capability,
        version: version,
        version_notes: version_notes,
        deprecation: deprecation,
        http_verb: http_verb,
        handler: handler,
        serializer: serializer,
        scope: scope,
        openapi: openapi,
        input_contract: input_contract,
        required_role: required_role
      )
    end

    def register_recordable_type_api(recordable_type, serializer: nil, output_keys: nil, fields: nil, openapi: nil,
                                     sortable_attributes: nil, writable_attributes: nil, immutable_fields: nil,
                                     relationships: nil, immutable_relationships: nil, operations: nil,
                                     capability_actions: nil, api: :public)
      definition = configuration.api(api)
      resolved_operations = operations
      resolved_operations = %i[index show] if resolved_operations.nil? && definition.respond_to?(:default_access) && definition.default_access == :read_only
      definition.recordable_registry.register(
        recordable_type,
        serializer: serializer,
        output_keys: output_keys,
        fields: fields,
        openapi: openapi,
        sortable_attributes: sortable_attributes,
        writable_attributes: writable_attributes,
        immutable_fields: immutable_fields,
        relationships: relationships,
        immutable_relationships: immutable_relationships,
        operations: resolved_operations,
        capability_actions: capability_actions
      )
    end

    def register_recording_studio_admin!
      Admin.register!
    end

    def capability_action(name, version: nil, api: :public)
      definition = configuration.fetch_api(api)
      definition.action_registry.resolve(name, profile: api_version_profile_for(version, api: api))
    end

    def capability_actions_for(recordable_type, version: nil, api: :public)
      definition = configuration.fetch_api(api)
      definition.action_registry.available_for(recordable_type, scope: :member, profile: api_version_profile_for(version, api: api)).select do |action|
        capability_action_enabled_for?(action, recordable_type, api: api)
      end
    end

    def capability_action_enabled_for?(action, recordable_type, api: :public)
      registration = recordable_registration_for(recordable_type, api: api)
      registration&.supports_capability_action?(action.name)
    end

    def resource_actions_for(recordable_type, scope: nil, version: nil, api: :public)
      definition = configuration.fetch_api(api)
      scopes = Array(scope.presence || %i[collection resource])
      scopes.flat_map do |entry_scope|
        definition.action_registry.available_for(recordable_type, scope: entry_scope, profile: api_version_profile_for(version, api: api))
      end.uniq
    end

    def resource_action(name, version: nil, api: :public)
      capability_action("resource_#{name}", version: version, api: api)
    end

    def recordable_registration_for(recordable_type, api: :public)
      configuration.fetch_api(api).recordable_registry[recordable_type]
    end

    def sortable_attributes_for(recordable_type, api: :public)
      registration = recordable_registration_for(recordable_type, api: api)
      configured = Array(registration&.sortable_attributes).map(&:to_s)

      (["created_at"] + configured).uniq
    end

    def resource_name_for(recordable_type)
      return "access" if recordable_type.to_s == "RecordingStudio::Access"

      recordable_type.to_s.demodulize.underscore.pluralize
    end

    def admin_dashboard_path(controller:, admin_api_recording: nil, **params)
      resolver = configuration.admin_dashboard_path_resolver

      if resolver.respond_to?(:call)
        path = resolver.call(controller: controller, admin_api_recording: admin_api_recording, **params)
        return path if path.present?
      end

      controller.recording_studio_api.admin_dashboard_path(params)
    end

    def admin_settings_path(controller:, **params)
      resolver = configuration.admin_settings_path_resolver

      if resolver.respond_to?(:call)
        path = resolver.call(controller: controller, **params)
        return path if path.present?
      end

      controller.recording_studio_api.admin_settings_path(params)
    end

    def admin_rate_limiting_path(controller:, **params)
      resolver = configuration.admin_rate_limiting_path_resolver

      if resolver.respond_to?(:call)
        path = resolver.call(controller: controller, **params)
        return path if path.present?
      end

      controller.recording_studio_api.admin_rate_limiting_path(params)
    end

    def admin_requests_path(controller:, **params)
      resolver = configuration.admin_requests_path_resolver

      if resolver.respond_to?(:call)
        path = resolver.call(controller: controller, **params)
        return path if path.present?
      end

      controller.recording_studio_api.admin_requests_path(params)
    end

    def admin_errors_path(controller:, **params)
      resolver = configuration.admin_errors_path_resolver

      if resolver.respond_to?(:call)
        path = resolver.call(controller: controller, **params)
        return path if path.present?
      end

      controller.recording_studio_api.admin_errors_path(params)
    end

    def admin_logs_path(controller:, **params)
      resolver = configuration.admin_logs_path_resolver

      if resolver.respond_to?(:call)
        path = resolver.call(controller: controller, **params)
        return path if path.present?
      end

      controller.recording_studio_api.admin_logs_path(params)
    end

    def recordable_type_for_resource(resource_name, api: :public)
      api_recordable_types(api: api).find { |recordable_type| resource_name_for(recordable_type) == resource_name.to_s }
    end

    def api_recordable_types(api: :public)
      definition = configuration.fetch_api(api)
      return definition.recordable_registry.to_h.keys unless definition.equal?(configuration.public_api)
      return [] unless defined?(RecordingStudio) && RecordingStudio.respond_to?(:configuration)

      Array(RecordingStudio.configuration.recordable_types).map(&:to_s).uniq.reject do |recordable_type|
        RecordingStudioApi::Engine.internal_recordable_type_names.include?(recordable_type)
      end
    end

    def api_access_point_recordable_types(api: :public)
      api_recordable_types(api: api).select do |recordable_type|
        api_access_point_recordable_type?(recordable_type, api: api)
      end
    end

    def api_access_point_recordable_type?(recordable_type, api: :public)
      type_name = recordable_type.to_s
      return false if type_name.blank?
      return false unless api_recordable_types(api: api).include?(type_name)
      return false unless defined?(RecordingStudio) && RecordingStudio.respond_to?(:capability_enabled?)

      RecordingStudio.capability_enabled?(:accessible, for: type_name) &&
        RecordingStudio.capability_enabled?(:api_access_point, for: type_name)
    end

    def api_versions(api: :public)
      definition = configuration.fetch_api(api)
      configured_versions = Array(definition.api_versions).filter_map { |version| normalize_api_version(version) }.uniq
      configured_versions.presence || [Configuration::DEFAULT_API_VERSION]
    end

    def default_api_version(api: :public)
      definition = configuration.fetch_api(api)
      configured_default = normalize_api_version(definition.default_api_version)
      return configured_default if configured_default.present? && api_versions(api: api).include?(configured_default)

      api_versions(api: api).first
    end

    def supported_api_version?(version, api: :public)
      normalized_version = normalize_api_version(version)
      normalized_version.present? && api_versions(api: api).include?(normalized_version)
    end

    def resolve_api_version(version, api: :public)
      normalized_version = normalize_api_version(version)
      return default_api_version(api: api) if normalized_version.blank?

      supported_api_version?(normalized_version, api: api) ? normalized_version : default_api_version(api: api)
    end

    def api_base_path(version: nil, mount_path: "/recording_studio_api", api_mount_path: "/api", api: :public)
      normalized_version = resolve_api_version(version, api: api)
      path_segments = [
        normalize_documentation_mount_path(mount_path),
        normalize_documentation_mount_path(api_mount_path, allow_root: false),
        normalized_version
      ].flat_map { |path| path.split("/") }.reject(&:blank?)

      "/#{path_segments.join('/')}"
    end

    def api_version_profile_for(version, api: :public)
      return if version.blank?

      configuration.fetch_api(api).api_version_profile_for(resolve_api_version(version, api: api))
    end

    def register_default_capability_actions!(api: nil)
      if api.nil?
        configuration.each_api { |definition| register_default_capability_actions!(api: definition.name) }
        return
      end
      return unless moveable_available? && capability_action(:move, api: api).nil?

      register_capability_action(
        :move,
        capability: :movable,
        http_verb: :post,
        required_role: :edit,
        handler: RecordingStudioApi::Services::MoveRecording,
        serializer: RecordingStudioApi::Serializers::ResourceRecordingSerializer,
        input_contract: {
          reject_unknown: true,
          fields: {
            parent_id: { type: :string, required: false, allow_blank: false },
            destination_id: { type: :string, required: false, allow_blank: false },
            new_parent_id: { type: :string, required: false, allow_blank: false }
          }
        },
        api: api
      )
    end

    def register_default_resource_actions!(api: nil)
      if api.nil?
        configuration.each_api { |definition| register_default_resource_actions!(api: definition.name) }
        return
      end

      register_capability_action(
        :resource_index,
        capability: nil,
        http_verb: :get,
        handler: RecordingStudioApi::Services::ResourceOperations::Index,
        scope: :collection,
        api: api
      ) unless capability_action(:resource_index, api: api)

      register_capability_action(
        :resource_show,
        capability: nil,
        http_verb: :get,
        handler: RecordingStudioApi::Services::ResourceOperations::Show,
        scope: :resource,
        api: api
      ) unless capability_action(:resource_show, api: api)

      register_capability_action(
        :resource_create,
        capability: nil,
        http_verb: :post,
        handler: RecordingStudioApi::Services::ResourceOperations::Create,
        scope: :collection,
        api: api
      ) unless capability_action(:resource_create, api: api)

      register_capability_action(
        :resource_update,
        capability: nil,
        http_verb: :patch,
        handler: RecordingStudioApi::Services::ResourceOperations::Update,
        scope: :resource,
        api: api
      ) unless capability_action(:resource_update, api: api)

      register_capability_action(
        :resource_destroy,
        capability: nil,
        http_verb: :delete,
        handler: RecordingStudioApi::Services::ResourceOperations::Destroy,
        scope: :resource,
        api: api
      ) unless capability_action(:resource_destroy, api: api)
    end

    private

    def normalize_documentation_mount_path(value, allow_root: true)
      path = value.to_s.strip
      path = "/#{path}" unless path.start_with?("/")
      path = path.squeeze("/").sub(%r{/\z}, "")
      path = "/" if path.empty?
      unless path.match?(%r{\A/[a-zA-Z0-9._~!$&'()*+,;=@/-]*\z}) && !path.include?("..")
        raise ArgumentError, "mount paths must be safe absolute paths"
      end

      return path if allow_root || path != "/"

      raise ArgumentError, "api_mount_path must not be the root path"
    end

    def normalize_api_version(value)
      normalized = value.to_s.strip.downcase
      return if normalized.blank?

      normalized.start_with?("v") ? normalized : "v#{normalized}"
    end

    def moveable_available?
      defined?(RecordingStudio::Moveable::Capabilities::Moveable) &&
        defined?(RecordingStudioApi::Services::MoveRecording)
    end
  end
end
# rubocop:enable Metrics/ModuleLength
