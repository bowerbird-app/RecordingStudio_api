# frozen_string_literal: true

require "action_dispatch/routing/mapper"

module RecordingStudioApi
  module Routing
    def recording_studio_api_scalar_docs_for(api_name, at:, as:, engine_mount_path: "/recording_studio_api")
      api_key = api_name.to_s
      mount_path = at.to_s.sub(%r{/+\z}, "")
      route_key = as.to_s
      defaults = { api_key: api_key, engine_mount_path: engine_mount_path }

      get mount_path,
          to: "recording_studio_api/scalar_docs#redirect_to_default",
          defaults: defaults,
          as: route_key
      get "#{mount_path}/:version/openapi.json",
          to: "recording_studio_api/scalar_docs#openapi",
          defaults: defaults,
          as: "#{route_key}_openapi"
      get "#{mount_path}/:version/fullscreen",
          to: "recording_studio_api/scalar_docs#fullscreen",
          defaults: defaults,
          as: "#{route_key}_fullscreen"
      get "#{mount_path}/:version",
          to: "recording_studio_api/scalar_docs#show",
          defaults: defaults,
          as: "#{route_key}_version"
    end
  end
end

ActionDispatch::Routing::Mapper.include(RecordingStudioApi::Routing)