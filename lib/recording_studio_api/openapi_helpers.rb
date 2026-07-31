# frozen_string_literal: true

module RecordingStudioApi
  module OpenapiHelpers
    def documentation_catalog(version: nil, mount_path: nil, api_mount_path: nil, api: :public)
      RecordingStudioApi::Services::DocumentationCatalog.call(
        version: version,
        mount_path: mount_path,
        api_mount_path: api_mount_path,
        api: api
      )
    end

    def openapi_document(version: nil, mount_path: nil, api_mount_path: nil, api: :public)
      RecordingStudioApi::Services::OpenapiDocument.call(
        version: version,
        mount_path: mount_path,
        api_mount_path: api_mount_path,
        api: api
      )
    end

    def recordable_details_schema_name_for(recordable_type)
      "#{recordable_type.to_s.delete(':')}Details"
    end

    def recordable_recording_schema_name_for(recordable_type)
      "#{recordable_type.to_s.delete(':')}Recording"
    end

    def openapi_title(api: :public)
      configured_title = configuration.fetch_api(api).openapi_title
      return configured_title if configured_title.present?

      host_application_name || "RecordingStudioApi"
    end

    def openapi_description(api: :public)
      configured_description = configuration.fetch_api(api).openapi_description
      return configured_description if configured_description.present?

      "API endpoints for accessing and managing Recording Studio resources."
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