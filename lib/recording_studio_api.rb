# frozen_string_literal: true

require "recording_studio_api/version"
require "recording_studio_api/engine"
require "recording_studio_api/errors"
require "recording_studio_api/configuration"
require "recording_studio_api/authenticated_client"
require "recording_studio_api/action_context"
require "recording_studio_api/accessible_recording_scope"
require "recording_studio_api/recordable_registry"
require "recording_studio_api/token"
require "recording_studio_api/oauth_access_token"
require "recording_studio_api/serializers/recording_serializer"
require "recording_studio_api/serializers/resource_recording_serializer"
require "recording_studio_api/services/base_service"
require "recording_studio_api/services/token_authentication_base"
require "recording_studio_api/services/example_service"
require "recording_studio_api/services/provision_api_client"
require "recording_studio_api/services/provision_access_request"
require "recording_studio_api/services/authenticate_bearer_token"
require "recording_studio_api/services/issue_oauth_access_token"
require "recording_studio_api/services/authenticate_oauth_access_token"
require "recording_studio_api/services/move_recording"
require "recording_studio_api/services/documentation_catalog"
require "recording_studio_api/services/openapi_document"

module RecordingStudioApi
  class << self
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

    def register_recordable_type_api(recordable_type, serializer: nil, openapi: nil)
      configuration.recordable_registry.register(
        recordable_type,
        serializer: serializer,
        openapi: openapi
      )
    end

    def capability_action(name)
      configuration.action_registry[name]
    end

    def capability_actions_for(recordable_type)
      configuration.action_registry.available_for(recordable_type)
    end

    def recordable_registration_for(recordable_type)
      configuration.recordable_registry[recordable_type]
    end

    def resource_name_for(recordable_type)
      recordable_type.to_s.demodulize.underscore.pluralize
    end

    def recordable_type_for_resource(resource_name)
      api_recordable_types.find { |recordable_type| resource_name_for(recordable_type) == resource_name.to_s }
    end

    def api_recordable_types
      return [] unless defined?(RecordingStudio) && RecordingStudio.respond_to?(:configuration)

      Array(RecordingStudio.configuration.recordable_types).map(&:to_s).uniq.reject do |recordable_type|
        recordable_type == "RecordingStudioApi::ApiClient"
      end
    end

    def register_default_capability_actions!
      return unless moveable_available?
      return if capability_action(:move)

      register_capability_action(
        :move,
        capability: :movable,
        http_verb: :post,
        handler: RecordingStudioApi::Services::MoveRecording,
        serializer: RecordingStudioApi::Serializers::ResourceRecordingSerializer
      )
    end

    def documentation_catalog
      RecordingStudioApi::Services::DocumentationCatalog.call
    end

    def openapi_document
      RecordingStudioApi::Services::OpenapiDocument.call
    end

    def recordable_details_schema_name_for(recordable_type)
      "#{recordable_type.to_s.delete(':')}Details"
    end

    def recordable_recording_schema_name_for(recordable_type)
      "#{recordable_type.to_s.delete(':')}Recording"
    end

    def openapi_title
      configured_title = if instance_variable_defined?(:@configuration)
                           @configuration&.openapi_title
                         end
      return configured_title if configured_title.present?

      host_application_name || "RecordingStudioApi"
    end

    private

    def host_application_name
      return unless defined?(Rails) && Rails.respond_to?(:application)

      application = Rails.application
      return unless application

      application.class.module_parent_name.presence
    end

    def moveable_available?
      defined?(RecordingStudio::Moveable::Capabilities::Moveable) &&
        defined?(RecordingStudioApi::Services::MoveRecording)
    end
  end
end
