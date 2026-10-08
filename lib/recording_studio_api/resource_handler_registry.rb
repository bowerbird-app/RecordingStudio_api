# frozen_string_literal: true

module RecordingStudioApi
  class ResourceHandlerRegistry
    def initialize
      @handlers = {}
    end

    def register(recordable_type, action, handler:)
      type_name = normalize_recordable_type(recordable_type)
      action_name = normalize_action(action)
      raise ConfigurationError, "recordable type is required" if type_name.blank?
      raise ConfigurationError, "action is required" if action_name.blank?
      raise ConfigurationError, "A callable handler is required" unless handler.respond_to?(:call)
      raise ConfigurationError, "Resource handler for #{type_name} #{action_name} is already registered" if @handlers.key?([type_name, action_name])

      @handlers[[type_name, action_name]] = handler
      handler
    end

    def fetch(recordable_type, action)
      @handlers[[normalize_recordable_type(recordable_type), normalize_action(action)]]
    end

    def to_h
      @handlers.each_with_object({}) do |((type_name, action_name), handler), listing|
        (listing[type_name] ||= {})[action_name] = handler_label(handler)
      end
    end

    def validate!
      @handlers.each do |(type_name, action_name), handler|
        next if handler.respond_to?(:call)

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
