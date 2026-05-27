# frozen_string_literal: true

module RecordingStudioApi
  class Engine < ::Rails::Engine
    isolate_namespace RecordingStudioApi

    class << self
      def apply_model_extensions(target)
        apply_extensions(target,
                         RecordingStudioApi.configuration.hooks.model_extensions_for(extension_keys_for(target)))
      end

      def apply_controller_extensions(target)
        apply_extensions(target,
                         RecordingStudioApi.configuration.hooks.controller_extensions_for(extension_keys_for(target)))
      end

      private

      def apply_extensions(target, extensions)
        return unless target

        applied = target.instance_variable_get(:@recording_studio_api_applied_extensions) || identity_hash

        extensions.flatten.compact.each do |extension|
          next if applied[extension]

          target.class_eval(&extension)
          applied[extension] = true
        end

        target.instance_variable_set(:@recording_studio_api_applied_extensions, applied)
      end

      def extension_keys_for(target)
        names = [target.name, target.name&.demodulize].compact.uniq
        names.map(&:to_sym)
      end

      def identity_hash
        {}.compare_by_identity
      end
    end

    # Run before_initialize hooks
    initializer "recording_studio_api.before_initialize", before: "recording_studio_api.load_config" do |_app|
      RecordingStudioApi::Hooks.run(:before_initialize, self)
    end

    initializer "recording_studio_api.load_config" do |app|
      # Load config/recording_studio_api.yml via Rails config_for if present
      if app.respond_to?(:config_for)
        begin
          yaml = begin
            app.config_for(:recording_studio_api)
          rescue StandardError
            nil
          end
          RecordingStudioApi.configuration.merge!(yaml) if yaml.respond_to?(:each)
        rescue StandardError => _e
          # ignore load errors; host app can provide initializer overrides
        end
      end

      # Merge Rails.application.config.x.recording_studio_api if present
      if app.config.respond_to?(:x) && app.config.x.respond_to?(:recording_studio_api)
        xcfg = app.config.x.recording_studio_api
        if xcfg.respond_to?(:to_h)
          RecordingStudioApi.configuration.merge!(xcfg.to_h)
        else
          begin
            # try converting OrderedOptions
            hash = {}
            xcfg.each_pair { |k, v| hash[k] = v } if xcfg.respond_to?(:each_pair)
            RecordingStudioApi.configuration.merge!(hash) if hash&.any?
          rescue StandardError => _e
            # ignore
          end
        end
      end

      # Run on_configuration hooks after config is loaded
      RecordingStudioApi::Hooks.run(:on_configuration, RecordingStudioApi.configuration)
    end

    # Run after_initialize hooks
    initializer "recording_studio_api.after_initialize", after: "recording_studio_api.load_config" do |_app|
      RecordingStudioApi::Engine.register_admin_api_recordable!
      RecordingStudioApi::Engine.register_api_client_recordable!
      RecordingStudioApi.register_default_capability_actions!
      RecordingStudioApi.register_default_resource_actions!
      RecordingStudioApi.configuration.validate!
      RecordingStudioApi::Hooks.run(:after_initialize, self)
    end

    # Apply model extensions when models are loaded
    initializer "recording_studio_api.apply_model_extensions" do
      config.to_prepare do
        next unless defined?(ActiveRecord::Base)

        ActiveRecord::Base.descendants.each do |model|
          next if model.abstract_class?

          RecordingStudioApi::Engine.apply_model_extensions(model)
        end
      end
    end

    # Apply controller extensions
    initializer "recording_studio_api.apply_controller_extensions" do
      config.to_prepare do
        next unless defined?(ActionController::Base)

        ActionController::Base.descendants.each do |controller|
          RecordingStudioApi::Engine.apply_controller_extensions(controller)
        end
      end
    end

    def self.register_api_client_recordable!
      register_recordable_type!("RecordingStudioApi::ApiClient")
    end

    def self.register_admin_api_recordable!
      register_recordable_type!("RecordingStudioApi::AdminApi")
    end

    def self.register_recordable_type!(recordable_type_name)
      return unless defined?(RecordingStudio) && RecordingStudio.respond_to?(:register_recordable_type)

      recordable_type = recordable_type_name.safe_constantize
      return if recordable_type.nil?

      RecordingStudio.register_recordable_type(recordable_type.name)
    end
  end
end
