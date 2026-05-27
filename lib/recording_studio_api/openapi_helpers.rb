# frozen_string_literal: true

module RecordingStudioApi
  module OpenapiHelpers
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
      configured_title = @configuration&.openapi_title if instance_variable_defined?(:@configuration)
      return configured_title if configured_title.present?

      host_application_name || "RecordingStudioApi"
    end

    def openapi_description
      configured_description = @configuration&.openapi_description if instance_variable_defined?(:@configuration)
      return configured_description if configured_description.present?

      "Add you API intro description in the config file"
    end

    private

    def host_application_name
      return unless defined?(Rails) && Rails.respond_to?(:application)

      application = Rails.application
      return unless application

      application.class.module_parent_name.presence
    end
  end
end