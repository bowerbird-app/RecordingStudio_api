# frozen_string_literal: true

module RecordingStudioApi
  class ScalarDocsController < ApplicationController
    layout :scalar_docs_layout

    before_action :load_api_definition
    before_action :ensure_documentation_enabled
    before_action :authorize_documentation
    before_action :ensure_supported_api_version, except: :redirect_to_default
    before_action :prepare_documentation_extension, only: :show

    def redirect_to_default
      redirect_to "#{request.path.chomp('/')}/#{@api_definition.default_api_version}"
    end

    def show
      prepare_scalar_reference
      vary_on_cookie! if @api_definition.documentation_access == :public

      render :fullscreen, layout: false if anonymous_public_documentation?
    end

    def fullscreen
      prepare_scalar_reference
      render :fullscreen, layout: false
    end

    def openapi
      arguments = {
        version: api_version,
        mount_path: params.fetch(:engine_mount_path, "/recording_studio_api"),
        api_mount_path: @api_definition.name == "public" ? "/api" : @api_definition.mount_path
      }
      arguments[:api] = @api_definition.name unless @api_definition.name == "public"

      render json: RecordingStudioApi::Services::OpenapiDocument.call(**arguments)
    rescue StandardError
      render plain: "Unable to generate the OpenAPI document.", status: :service_unavailable
    end

    private

    def prepare_scalar_reference
      @api_version = api_version
      @api_title = @api_definition.openapi_title.presence || "#{@api_definition.name.humanize} API"
      version_path = request.path.delete_suffix("/fullscreen")
      @scalar_url = "#{version_path}/openapi.json"
      @fullscreen_url = "#{version_path}/fullscreen"
      @scalar_configuration_json = ERB::Util.json_escape(
        { url: @scalar_url, layout: "modern" }.to_json
      )
    end

    def anonymous_public_documentation?
      @api_definition.documentation_access == :public && documentation_actor.blank?
    end

    def vary_on_cookie!
      response.headers["Vary"] = response.headers["Vary"].to_s.split(",").map(&:strip).append("Cookie").reject(&:blank?).uniq.join(", ")
    end

    def load_api_definition
      @api_definition = RecordingStudioApi.configuration.fetch_api(params.fetch(:api_key))
    rescue RecordingStudioApi::ConfigurationError, KeyError
      head :not_found
    end

    def ensure_documentation_enabled
      head :not_found unless @api_definition&.documentation_enabled
    end

    def authorize_documentation
      return if performed?

      access = @api_definition.documentation_access
      return if access == :public

      actor = documentation_actor
      if access == :authenticated
        head :unauthorized if actor.blank?
        return
      end

      authorized = access.respond_to?(:call) && access.call(
        controller: self,
        actor: actor,
        api: @api_definition.name
      )
      head(actor.present? ? :forbidden : :unauthorized) unless authorized
    end

    def ensure_supported_api_version
      return if RecordingStudioApi.supported_api_version?(api_version, api: @api_definition.name)

      render plain: "Unsupported API version. Supported versions: #{RecordingStudioApi.api_versions(api: @api_definition.name).join(', ')}.", status: :not_found
    end

    def api_version
      params.fetch(:version).to_s.downcase
    end

    def documentation_actor
      return send(:current_user) if respond_to?(:current_user, true) && send(:current_user).present?
      return Current.actor if defined?(Current) && Current.respond_to?(:actor)

      nil
    end

    def scalar_docs_layout
      @api_definition&.documentation_layout_name.presence ||
        RecordingStudioApi.configuration.layout_name.presence ||
        "recording_studio/default_layout"
    end

    def prepare_documentation_extension
      send(:prepare_scalar_documentation) if respond_to?(:prepare_scalar_documentation, true)
    end
  end
end