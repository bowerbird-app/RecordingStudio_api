# frozen_string_literal: true

module OperationsApi
class ScalarDocsController < ApplicationController
  layout "flat_pack_sidebar"

  before_action :authorize_scalar_documentation!
  before_action :ensure_supported_api_version

  def show
    @scalar_url = configured_scalar_url || helpers.operations_api_scalar_docs_openapi_path(version: api_version)
    @fullscreen_url = helpers.operations_api_scalar_docs_fullscreen_path(version: api_version)
    @scalar_source = "https://cdn.jsdelivr.net/npm/@scalar/api-reference@1.64.0/dist/browser/standalone.js"
    @scalar_integrity = nil
    @scalar_configuration_json = ERB::Util.json_escape(
      { url: @scalar_url, layout: "modern" }.to_json
    )
  end

  def fullscreen
    show
    render :fullscreen, layout: false
  end

  def openapi
    render json: openapi_provider.call(
      version: api_version,
      mount_path: "/recording_studio_api",
      api_mount_path: "/apis/operations",
      api: "operations"
    )
  rescue StandardError
    render plain: "Unable to generate the OpenAPI document. Check the configured OpenAPI provider.", status: :service_unavailable
  end

  private

  def authorize_scalar_documentation!
    authorized = admin_root_current? && RecordingStudioApi::Admin::ApiAuthorization.authorized?(
      actor: current_user,
      api: :operations,
      root_recording: current_root_recording,
      role: RecordingStudioApi.configuration.access_management_view_role,
      create: true
    )

    head :forbidden unless authorized
  end

  def api_version
    params.fetch(:version).to_s.downcase
  end

  def ensure_supported_api_version
    return if RecordingStudioApi.supported_api_version?(api_version, api: "operations")

    render plain: "Unsupported API version. Supported versions: #{RecordingStudioApi.api_versions(api: "operations").join(', ')}.", status: :not_found
  end

  def openapi_provider
    RecordingStudioApi::Services::OpenapiDocument
  end

  def configured_scalar_url
    value = nil
    value.presence
  end
end
end
