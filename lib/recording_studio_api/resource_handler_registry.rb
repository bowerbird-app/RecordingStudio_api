# frozen_string_literal: true

require_relative "handler_scope"

module RecordingStudioApi
  class ResourceHandlerRegistration
    attr_reader :handler, :include_trashed, :owns_scoping, :trashed_semantics, :creates, :parent

    def initialize(handler:, include_trashed:, owns_scoping:, trashed_semantics:, creates:, parent: nil)
      @handler = handler
      @include_trashed = include_trashed
      @owns_scoping = owns_scoping
      @trashed_semantics = trashed_semantics
      @creates = creates
      @parent = parent
    end

    def creates?
      creates
    end

    def server_parent?
      CreateParent.server?(parent)
    end

    def call(context)
      handler.call(context)
    end

    def owns_scoping?
      owns_scoping
    end
  end

  class ResourceHandlerRegistry
    def initialize
      @handlers = {}
    end

    def register(recordable_type, action, handler:, include_trashed: false, owns_scoping: false, trashed_semantics: nil, creates: false, parent: nil, api: :public)
      type_name = normalize_recordable_type(recordable_type)
      action_name = normalize_action(action)
      raise ConfigurationError, "recordable type is required" if type_name.blank?
      raise ConfigurationError, "action is required" if action_name.blank?
      raise ConfigurationError, "A callable handler is required" unless handler.respond_to?(:call)
      raise ConfigurationError, "Resource handler for #{type_name} #{action_name} is already registered" if @handlers.key?([type_name, action_name])

      include_trashed = HandlerScope.flag(include_trashed, name: :include_trashed)
      owns_scoping = HandlerScope.flag(owns_scoping, name: :owns_scoping)
      creates = HandlerScope.flag(creates, name: :creates)
      parent = normalize_parent(parent, action_name)
      label = "#{type_name} #{action_name}"
      trashed_semantics = HandlerScope.trashed_semantics(trashed_semantics, name: label)
      if trashed_semantics
        verb, role = HandlerScope.resource_handler_verb_and_role(action_name, api: api)
        HandlerScope.assert_trashed_semantics!(
          name: label,
          trashed_semantics: trashed_semantics,
          http_verb: verb,
          required_role: role,
          owns_scoping: owns_scoping
        )
      end
      HandlerScope.assert_include_trashed!(name: label, action_name: action_name, api: api, trashed_semantics: trashed_semantics) if include_trashed

      @handlers[[type_name, action_name]] = ResourceHandlerRegistration.new(
        handler: handler,
        include_trashed: include_trashed,
        owns_scoping: owns_scoping,
        trashed_semantics: trashed_semantics,
        creates: creates,
        parent: parent
      )
      handler
    end

    def registration(recordable_type, action)
      @handlers[[normalize_recordable_type(recordable_type), normalize_action(action)]]
    end

    def fetch(recordable_type, action)
      registration(recordable_type, action)&.handler
    end

    def to_h
      @handlers.each_with_object({}) do |((type_name, action_name), registration), listing|
        (listing[type_name] ||= {})[action_name] = handler_label(registration.handler)
      end
    end

    def validate!
      @handlers.each do |(type_name, action_name), registration|
        next if registration.handler.respond_to?(:call)

        raise ConfigurationError, "A callable handler is required for #{type_name} #{action_name}"
      end
    end

    private

    def normalize_recordable_type(value)
      value.to_s.strip
    end

    def normalize_parent(value, action_name)
      return if value.nil?

      parent = CreateParent.normalize(value, name: "parent")
      return unless CreateParent.server?(parent)
      return parent if action_name == "create"

      raise ConfigurationError, "parent: :server is only valid for a create handler"
    end

    def normalize_action(value)
      value.to_s.strip
    end

    def handler_label(handler)
      name = handler.name if handler.respond_to?(:name)
      return name if name.present?

      handler.class.name
    end
  end
end
