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
        apply_extensions(target, collected_extensions(target, :model_extensions_for))
      end

      def apply_controller_extensions(target)
        apply_extensions(target, collected_extensions(target, :controller_extensions_for))
      end

      def apply_loaded_controller_extensions
        each_action_controller { |controller| apply_controller_extensions(controller) }
      end

      def action_controller_subclass?(value)
        return false unless value.is_a?(Class)

        action_controller_parents.any? { |parent| value < parent }
      end

      def watch_autoloaded_controllers
        return if @watching_autoloaded_controllers
        return unless defined?(Rails) && Rails.application

        @watching_autoloaded_controllers = true
        Rails.autoloaders.each do |loader|
          loader.on_load do |_constant_path, value, _file|
            next unless RecordingStudioApi::Engine.action_controller_subclass?(value)

            RecordingStudioApi::Engine.apply_controller_extensions(value)
          end
        end
      end

      private

      def each_action_controller(&block)
        action_controller_parents.each do |parent|
          parent.descendants.each(&block)
        end
      end

      def action_controller_parents
        %w[ActionController::Base ActionController::API].filter_map do |parent_name|
          parent = loaded_constant(parent_name)
          parent if parent.respond_to?(:descendants)
        end
      end

      def loaded_constant(name)
        name.split("::").reduce(Object) do |namespace, part|
          return nil unless namespace.const_defined?(part, false)
          return nil if namespace.autoload?(part)

          namespace.const_get(part, false)
        end
      end

      def apply_extensions(target, extensions)
        return unless target

        applied = target.instance_variable_get(:@recording_studio_api_applied_extensions) || identity_hash
        target.instance_variable_set(:@recording_studio_api_applied_extensions, applied)

        extensions.flatten.compact.each do |extension|
          next if applied[extension]

          target.class_eval(&extension)
          applied[extension] = true
        end
      end

      def collected_extensions(target, reader)
        extension_keys_for(target).flat_map do |name|
          RecordingStudioApi.configuration.hooks.public_send(reader, name)
        end
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
      RecordingStudioApi.configuration.hooks.run(:before_initialize, self)
    end

    initializer "recording_studio_api.load_config" do |app|
      if app.respond_to?(:config_for)
        yaml = app.config_for(:recording_studio_api)
        RecordingStudioApi.configuration.merge!(yaml) if yaml.respond_to?(:each)
      end

      if app.config.respond_to?(:x) && app.config.x.respond_to?(:recording_studio_api)
        xcfg = app.config.x.recording_studio_api
        if xcfg.respond_to?(:to_h)
          RecordingStudioApi.configuration.merge!(xcfg.to_h)
        elsif xcfg.respond_to?(:each_pair)
          hash = {}
          xcfg.each_pair { |key, value| hash[key] = value }
          RecordingStudioApi.configuration.merge!(hash) if hash.any?
        end
      end

      RecordingStudioApi.configuration.hooks.run(:on_configuration, RecordingStudioApi.configuration)
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
        RecordingStudioApi.prepare_recordable_registries_for_reload!
        RecordingStudioApi::Engine.register_recordable_types!
        RecordingStudio::DelegatedTypeRegistrar.apply! if defined?(RecordingStudio::DelegatedTypeRegistrar)
      end
    end

    # Run after_initialize hooks
    initializer "recording_studio_api.after_initialize", after: "recording_studio_api.load_config" do |_app|
      RecordingStudioApi.register_default_capability_actions!
      RecordingStudioApi.register_default_resource_actions!
      RecordingStudioApi.configuration.validate!
      RecordingStudioApi.configuration.hooks.run(:after_initialize, self)
    end

    initializer "recording_studio_api.flush_request_log_batches" do
      next unless defined?(ActiveSupport::Executor)

      ActiveSupport::Executor.to_complete do
        RecordingStudioApi::Engine.complete_request!
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

    # Apply controller extensions to ActionController::Base and ActionController::API.
    initializer "recording_studio_api.apply_controller_extensions" do
      RecordingStudioApi::Engine.watch_autoloaded_controllers

      config.to_prepare do
        RecordingStudioApi::Engine.apply_loaded_controller_extensions
      end
    end

    initializer "recording_studio_api.register_recording_studio_admin", after: "recording_studio_api.after_initialize" do
      config.to_prepare do
        RecordingStudioApi.register_recording_studio_admin!
      end
    end

    initializer "recording_studio_api.logs" do
      config.to_prepare { RecordingStudioApi::LogsRegistration.register! }
    end

    initializer "recording_studio_api.metrics" do
      config.to_prepare { RecordingStudioApi::Metrics.register! }
    end

    def self.complete_request!
      ApiRequestLogBatch.flush!
      clear_admin_credentials_query_cache!
    end

    def self.clear_admin_credentials_query_cache!
      return unless admin_loaded?

      Admin::Queries::AdminApiCredentialsQuery.clear_cache!
    end

    def self.admin_loaded?
      defined?(Admin) && Admin.respond_to?(:available?) && Admin.available? &&
        defined?(Admin::Queries::AdminApiCredentialsQuery)
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
