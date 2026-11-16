# frozen_string_literal: true

require_relative "handler_scope"

module RecordingStudioApi
  class ResourceHandlerRegistration
    attr_reader :handler, :include_trashed, :owns_scoping

    def initialize(handler:, include_trashed:, owns_scoping:)
      @handler = handler
      @include_trashed = include_trashed
      @owns_scoping = owns_scoping
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

    def register(recordable_type, action, handler:, include_trashed: false, owns_scoping: false, api: :public)
      type_name = normalize_recordable_type(recordable_type)
      action_name = normalize_action(action)
      raise ConfigurationError, "recordable type is required" if type_name.blank?
      raise ConfigurationError, "action is required" if action_name.blank?
      raise ConfigurationError, "A callable handler is required" unless handler.respond_to?(:call)
      raise ConfigurationError, "Resource handler for #{type_name} #{action_name} is already registered" if @handlers.key?([type_name, action_name])

      include_trashed = HandlerScope.flag(include_trashed, name: :include_trashed)
      owns_scoping = HandlerScope.flag(owns_scoping, name: :owns_scoping)
      HandlerScope.assert_read_opt_out!(name: "#{type_name} #{action_name}", action_name: action_name, api: api) if owns_scoping

      @handlers[[type_name, action_name]] = ResourceHandlerRegistration.new(
        handler: handler,
        include_trashed: include_trashed,
        owns_scoping: owns_scoping
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
