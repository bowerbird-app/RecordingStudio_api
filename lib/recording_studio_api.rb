# frozen_string_literal: true

require "recording_studio_api/version"
require "recording_studio_accessible"
require "recording_studio_api/engine"
require "recording_studio_api/errors"
require "recording_studio_api/configuration"
require "recording_studio_api/authenticated_client"
require "recording_studio_api/access_grant"
require "recording_studio_api/action_context"
require "recording_studio_api/resource_operation_context"
require "recording_studio_api/accessible_recording_scope"
require "recording_studio_api/access_policy"
require "recording_studio_api/recordable_registry"
require "recording_studio_api/token"
require "recording_studio_api/oauth_access_token"
require "recording_studio_api/oauth_refresh_token_value"
require "recording_studio_api/oauth_error_mapper"
require "recording_studio_api/openapi_helpers"
require "recording_studio_api/serializers/recording_serializer"
require "recording_studio_api/serializers/resource_recording_serializer"
require "recording_studio_api/services/base_service"
require "recording_studio_api/services/token_authentication_base"
require "recording_studio_api/access_management_policy"
require "recording_studio_api/services/example_service"
require "recording_studio_api/services/provision_api_client"
require "recording_studio_api/services/provision_access_request"
require "recording_studio_api/services/authenticate_bearer_token"
require "recording_studio_api/services/issue_oauth_access_token"
require "recording_studio_api/services/authenticate_oauth_access_token"
require "recording_studio_api/services/authorize_oauth_client"
require "recording_studio_api/services/exchange_oauth_authorization_code"
require "recording_studio_api/services/refresh_oauth_access_token"
require "recording_studio_api/services/revoke_oauth_token"
require "recording_studio_api/services/revoke_oauth_grant_session"
require "recording_studio_api/services/move_recording"
require "recording_studio_api/services/documentation_catalog"
require "recording_studio_api/services/openapi_document"
require "recording_studio_api/services/paginate_resource_collection"
require "recording_studio_api/services/resource_operations/base"
require "recording_studio_api/services/resource_operations/index"
require "recording_studio_api/services/resource_operations/show"
require "recording_studio_api/services/resource_operations/create"
require "recording_studio_api/services/resource_operations/update"
require "recording_studio_api/services/resource_operations/destroy"
require "recording_studio_api/services/trashable_operations/restore"
require "recording_studio_api/services/trashable_operations/destroy"

module RecordingStudioApi
  class << self
    include OpenapiHelpers

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
    end

    def register_capability_action(name, capability:, http_verb: :post, handler:, serializer: nil, scope: :member, openapi: nil, input_contract: nil)
      configuration.action_registry.register(
        name,
        capability: capability,
        http_verb: http_verb,
        handler: handler,
        serializer: serializer,
        scope: scope,
        openapi: openapi,
        input_contract: input_contract
      )
    end

    def register_recordable_type_api(recordable_type, serializer: nil, openapi: nil, sortable_attributes: nil)
      configuration.recordable_registry.register(
        recordable_type,
        serializer: serializer,
        openapi: openapi,
        sortable_attributes: sortable_attributes
      )
    end

    def capability_action(name)
      configuration.action_registry[name]
    end

    def capability_actions_for(recordable_type)
      configuration.action_registry.available_for(recordable_type, scope: :member)
    end

    def resource_actions_for(recordable_type, scope: nil)
      scopes = Array(scope.presence || %i[collection resource])
      scopes.flat_map do |entry_scope|
        configuration.action_registry.available_for(recordable_type, scope: entry_scope)
      end.uniq
    end

    def resource_action(name)
      capability_action("resource_#{name}")
    end

    def recordable_registration_for(recordable_type)
      configuration.recordable_registry[recordable_type]
    end

    def sortable_attributes_for(recordable_type)
      registration = recordable_registration_for(recordable_type)
      configured = Array(registration&.sortable_attributes).map(&:to_s)

      (["created_at"] + configured).uniq
    end

    def resource_name_for(recordable_type)
      return "access" if recordable_type.to_s == "RecordingStudio::Access"

      recordable_type.to_s.demodulize.underscore.pluralize
    end

    def admin_dashboard_path(controller:, admin_api_recording: nil)
      resolver = configuration.admin_dashboard_path_resolver

      if resolver.respond_to?(:call)
        path = resolver.call(controller: controller, admin_api_recording: admin_api_recording)
        return path if path.present?
      end

      controller.recording_studio_api.admin_dashboard_path
    end

    def admin_logs_path(controller:, **params)
      resolver = configuration.admin_logs_path_resolver

      if resolver.respond_to?(:call)
        path = resolver.call(controller: controller, **params)
        return path if path.present?
      end

      controller.recording_studio_api.admin_logs_path(params)
    end

    def recordable_type_for_resource(resource_name)
      api_recordable_types.find { |recordable_type| resource_name_for(recordable_type) == resource_name.to_s }
    end

    def api_recordable_types
      return [] unless defined?(RecordingStudio) && RecordingStudio.respond_to?(:configuration)

      Array(RecordingStudio.configuration.recordable_types).map(&:to_s).uniq.reject do |recordable_type|
        RecordingStudioApi::Engine.internal_recordable_type_names.include?(recordable_type)
      end
    end

    def register_default_capability_actions!
      if moveable_available? && capability_action(:move).nil?
        register_capability_action(
          :move,
          capability: :movable,
          http_verb: :post,
          handler: RecordingStudioApi::Services::MoveRecording,
          serializer: RecordingStudioApi::Serializers::ResourceRecordingSerializer
        )
      end

      register_capability_action(
        :trash_restore,
        capability: :trashable,
        http_verb: :post,
        handler: RecordingStudioApi::Services::TrashableOperations::Restore,
        scope: :resource
      ) unless capability_action(:trash_restore)

      register_capability_action(
        :trash_destroy,
        capability: :trashable,
        http_verb: :delete,
        handler: RecordingStudioApi::Services::TrashableOperations::Destroy,
        scope: :resource
      ) unless capability_action(:trash_destroy)
    end

    def register_default_resource_actions!
      register_capability_action(
        :resource_index,
        capability: nil,
        http_verb: :get,
        handler: RecordingStudioApi::Services::ResourceOperations::Index,
        scope: :collection
      ) unless capability_action(:resource_index)

      register_capability_action(
        :resource_show,
        capability: nil,
        http_verb: :get,
        handler: RecordingStudioApi::Services::ResourceOperations::Show,
        scope: :resource
      ) unless capability_action(:resource_show)

      register_capability_action(
        :resource_create,
        capability: nil,
        http_verb: :post,
        handler: RecordingStudioApi::Services::ResourceOperations::Create,
        scope: :collection
      ) unless capability_action(:resource_create)

      register_capability_action(
        :resource_update,
        capability: nil,
        http_verb: :patch,
        handler: RecordingStudioApi::Services::ResourceOperations::Update,
        scope: :resource
      ) unless capability_action(:resource_update)

      register_capability_action(
        :resource_destroy,
        capability: nil,
        http_verb: :delete,
        handler: RecordingStudioApi::Services::ResourceOperations::Destroy,
        scope: :resource
      ) unless capability_action(:resource_destroy)
    end

    private

    def moveable_available?
      defined?(RecordingStudio::Moveable::Capabilities::Moveable) &&
        defined?(RecordingStudioApi::Services::MoveRecording)
    end
  end
end
