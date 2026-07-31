# frozen_string_literal: true

module PublicApi
class ScalarDocsController < ApplicationController
  # BEGIN RecordingStudioApi test auth: public_api
  include PublicApi::ScalarTestAuth
  before_action :load_scalar_test_auth, only: :show
  # END RecordingStudioApi test auth: public_api
  layout "flat_pack_sidebar"

  before_action :authorize_scalar_documentation!
  before_action :ensure_supported_api_version

  def show
    @api_version = api_version
    @scalar_url = configured_scalar_url || helpers.public_api_scalar_docs_openapi_path(version: api_version)
    @fullscreen_url = helpers.public_api_scalar_docs_fullscreen_path(version: api_version)
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
      api_mount_path: "/api"
    )
  rescue StandardError
    render plain: "Unable to generate the OpenAPI document. Check the configured OpenAPI provider.", status: :service_unavailable
  end

  private

  # Implement this hook with your host application's authentication and authorization policy.
  # Leaving it unchanged intentionally keeps this documentation installation public.
  def authorize_scalar_documentation!
  end

  def api_version
    params.fetch(:version).to_s.downcase
  end

  def ensure_supported_api_version
    return if RecordingStudioApi.supported_api_version?(api_version, api: "public")

    render plain: "Unsupported API version. Supported versions: #{RecordingStudioApi.api_versions(api: "public").join(', ')}.", status: :not_found
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
