# frozen_string_literal: true

require_relative "hooks"
require_relative "action_registry"
require_relative "recordable_registry"

module RecordingStudioApi
  class Configuration
    attr_accessor :enable_feature_x, :timeout, :token_ttl, :openapi_title
    attr_reader :hooks, :action_registry, :recordable_registry

    def initialize
      @enable_feature_x = false
      @timeout = 5
      @token_ttl = 30.respond_to?(:days) ? 30.days : 30 * 24 * 60 * 60
      @openapi_title = nil
      @hooks = Hooks.new
      @action_registry = ActionRegistry.new
      @recordable_registry = RecordableRegistry.new
    end

    def to_h
      {
        enable_feature_x: enable_feature_x,
        timeout: timeout,
        token_ttl: token_ttl,
        openapi_title: openapi_title,
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
    end
  end
end
