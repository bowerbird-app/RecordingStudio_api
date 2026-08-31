# frozen_string_literal: true

module RecordingStudioApi
  class Engine < ::Rails::Engine
    isolate_namespace RecordingStudioApi

    API_RECORDABLE_TYPE_NAMES = %w[
      RecordingStudio::Access
      RecordingStudioApi::ApiClient
      RecordingStudioApi::ApiCredential
      RecordingStudioApi::ApiAccessToken
    ].freeze

    ADMIN_API_RECORDABLE_TYPE_NAME = "RecordingStudioApi::AdminApi"

    RECORDABLE_MODEL_DEPENDENCIES = {
      "RecordingStudio::Access" => "recording_studio/access",
      "RecordingStudioApi::ApiClient" => "recording_studio_api/api_client",
      "RecordingStudioApi::ApiCredential" => "recording_studio_api/api_credential",
      "RecordingStudioApi::ApiAccessToken" => "recording_studio_api/api_access_token"
    }.freeze

    API_RECORDABLE_DECLARATIONS = {
      "RecordingStudioApi::ApiClient" => {
        label: "API Client",
        plural_label: "API Clients",
        root: false,
        allowed_parent_types: ["RecordingStudio::Access"]
      },
      "RecordingStudioApi::ApiCredential" => {
        label: "API Credential",
        plural_label: "API Credentials",
        root: false,
        allowed_parent_types: ["RecordingStudioApi::ApiClient"]
      },
      "RecordingStudioApi::ApiAccessToken" => {
        label: "API Access Token",
        plural_label: "API Access Tokens",
        root: false,
        allowed_parent_types: ["RecordingStudioApi::ApiCredential"]
      }
    }.freeze

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

    initializer "recording_studio_api.assets" do |app|
      next unless app.config.respond_to?(:assets)

      app.config.assets.precompile += [RecordingStudioApi::ScalarAsset::LOGICAL_PATH]
    end

    initializer "recording_studio_api.register_recordable_types", after: "recording_studio.load_config" do
      RecordingStudio::RecordableDeclarations.install_active_record_macro! if defined?(RecordingStudio::RecordableDeclarations)
      RecordingStudioApi::Engine.load_recordable_models!
      RecordingStudioApi::Engine.register_recordable_types!

      config.to_prepare do
        RecordingStudioApi::Engine.register_recordable_types!
        RecordingStudio::DelegatedTypeRegistrar.apply! if defined?(RecordingStudio::DelegatedTypeRegistrar)
      end
    end

    # Run after_initialize hooks
    initializer "recording_studio_api.after_initialize", after: "recording_studio_api.load_config" do |_app|
      RecordingStudioApi.register_default_capability_actions!
      RecordingStudioApi.register_default_resource_actions!
      RecordingStudioApi.configuration.validate!
      RecordingStudioApi::Hooks.run(:after_initialize, self)
    end

    initializer "recording_studio_api.delegated_oauth_voiding", after: "recording_studio_api.after_initialize" do
      config.to_prepare do
        RecordingStudioApi::DelegatedOauthVoiding.install!
      end
    end

    initializer "recording_studio_api.flush_request_log_batches" do
      next unless defined?(ActiveSupport::Executor)

      ActiveSupport::Executor.to_complete do
        RecordingStudioApi::ApiRequestLogBatch.flush!
        RecordingStudioApi::Admin::Queries::AdminApiCredentialsQuery.clear_cache!
      rescue StandardError => e
        Rails.logger.warn("[RecordingStudioApi] request completion cleanup failed: #{e.class}: #{e.message}")
      end
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

    initializer "recording_studio_api.register_recording_studio_admin", after: "recording_studio_api.after_initialize" do
      config.to_prepare do
        RecordingStudioApi.register_recording_studio_admin!
      end
    end

    initializer "recording_studio_api.prepend_recording_studio_admin_views", after: "recording_studio_api.register_recording_studio_admin" do
      config.to_prepare do
        require_dependency "recording_studio_admin/screens_controller"

        view_path = RecordingStudioApi::Engine.root.join("app/views").to_s
        [
          (RecordingStudioAdmin::ApplicationController if defined?(RecordingStudioAdmin::ApplicationController)),
          (RecordingStudioAdmin::ScreensController if defined?(RecordingStudioAdmin::ScreensController))
        ].compact.each do |controller|
          next if controller.view_paths.first.to_s == view_path

          controller.prepend_view_path(view_path)
        end
      end
    end

    def self.register_recordable_types!
      return unless defined?(RecordingStudio) && RecordingStudio.respond_to?(:configuration)
      return unless defined?(RecordingStudio::RecordableDeclarations)

      RecordingStudio::RecordableDeclarations.install_active_record_macro!
      register_admin_root_recordable!

      declare_recordable_type!(
        "RecordingStudio::Access",
        label: "Access",
        plural_label: "Access",
        root: false
      )

      API_RECORDABLE_DECLARATIONS.each do |recordable_type_name, declaration|
        declare_recordable_type!(recordable_type_name, **declaration)
      end

      if admin_root_recordable_type_names.any?
        declare_recordable_type!(
          ADMIN_API_RECORDABLE_TYPE_NAME,
          label: "Admin API",
          plural_label: "Admin APIs",
          root: false,
          allowed_parent_types: admin_root_recordable_type_names
        )
      end

      register_recordable_type_names!(recordable_type_names_to_register)
    end

    def self.load_recordable_models!
      RECORDABLE_MODEL_DEPENDENCIES.each do |recordable_type_name, dependency|
        next if recordable_type_name.safe_constantize.present?

        require_dependency dependency
      end
    end

    def self.internal_recordable_type_names
      API_RECORDABLE_TYPE_NAMES + admin_root_recordable_type_names + [ADMIN_API_RECORDABLE_TYPE_NAME]
    end

    def self.register_admin_root_recordable!
      register_recordable_type_names!(admin_root_recordable_type_names)
    end

    def self.recordable_type_names_to_register
      type_names = API_RECORDABLE_TYPE_NAMES.dup
      type_names << ADMIN_API_RECORDABLE_TYPE_NAME if admin_root_recordable_type_names.any?
      type_names
    end

    def self.register_recordable_type_names!(recordable_type_names)
      existing_type_names = Array(RecordingStudio.configuration.recordable_types).map(&:to_s)
      available_type_names = recordable_type_names.select { |recordable_type_name| recordable_type_name.safe_constantize.present? }

      RecordingStudio.configuration.recordable_types = (existing_type_names + available_type_names).uniq
    end

    def self.internal_child_recordable_type_names
      API_RECORDABLE_TYPE_NAMES + [ADMIN_API_RECORDABLE_TYPE_NAME]
    end

    def self.declare_recordable_type!(recordable_type_name, **declaration)
      recordable_type = recordable_type_name.safe_constantize
      return unless recordable_type.respond_to?(:recording_studio_recordable)

      recordable_type.recording_studio_recordable(**declaration)
    end

    def self.declaration_defined?(recordable_type_name)
      RecordingStudio::RecordableDeclarations.declarations.key?(recordable_type_name)
    end

    def self.admin_root_recordable_type_names
      Array(RecordingStudioApi.configuration.admin_root_recordable_type_names).map(&:to_s).select do |recordable_type_name|
        recordable_type_name.safe_constantize.present?
      end
    end
  end
end
