# frozen_string_literal: true

require "recording_studio_api/version"
require "recording_studio_api/engine"
require "recording_studio_api/errors"
require "recording_studio_api/configuration"
require "recording_studio_api/authenticated_client"
require "recording_studio_api/action_context"
require "recording_studio_api/token"
require "recording_studio_api/serializers/recording_serializer"
require "recording_studio_api/services/base_service"
require "recording_studio_api/services/example_service"
require "recording_studio_api/services/provision_api_client"
require "recording_studio_api/services/authenticate_bearer_token"
require "recording_studio_api/services/move_recording"

module RecordingStudioApi
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
    end

    def register_capability_action(name, capability:, http_verb: :post, handler:, serializer: nil, scope: :member)
      configuration.action_registry.register(
        name,
        capability: capability,
        http_verb: http_verb,
        handler: handler,
        serializer: serializer,
        scope: scope
      )
    end

    def capability_action(name)
      configuration.action_registry[name]
    end

    def capability_actions_for(recordable_type)
      configuration.action_registry.available_for(recordable_type)
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
        serializer: RecordingStudioApi::Serializers::RecordingSerializer
      )
    end

    private

    def moveable_available?
      defined?(RecordingStudio::Moveable::Capabilities::Moveable) &&
        defined?(RecordingStudioApi::Services::MoveRecording)
    end
  end
end
