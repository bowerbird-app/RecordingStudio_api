# frozen_string_literal: true

RecordingStudioApi::Engine.routes.draw do
  short_action_constraint = lambda do |request|
    params = request.path_parameters
    path_segments = request.path.split("/").reject(&:blank?)
    api_index = path_segments.rindex("apis")
    api_key = (params[:api_key] || params["api_key"] || (api_index && path_segments[api_index + 1])).presence || "public"
    resource = params[:resource] || params["resource"] || path_segments[-3]
    action_name = params[:action_name] || params["action_name"] || path_segments.last
    recordable_type = RecordingStudioApi.recordable_type_for_resource(resource, api: api_key)
    registration = RecordingStudioApi.recordable_registration_for(recordable_type, api: api_key) if recordable_type

    !registration&.relationships&.key?(action_name.to_s)
  rescue RecordingStudioApi::ConfigurationError
    true
  end

  get "/admin_api", to: "admin_dashboards#show", as: :admin_dashboard
  get "/admin_api/settings", to: "admin_settings#show", as: :admin_settings
  patch "/admin_api/settings/api_access", to: "admin_settings#update_api_access", as: :admin_api_access_settings
  get "/admin_api/rate_limiting", to: "admin_rate_limitings#show", as: :admin_rate_limiting
  get "/admin_api/requests", to: "admin_requests#index", as: :admin_requests
  get "/admin_api/errors", to: "admin_errors#index", as: :admin_errors
  get "/admin_api/logs", to: "admin_logs#index", as: :admin_logs
  post "/admin_api/credentials/:id/revoke", to: "admin_credentials#revoke", as: :admin_revoke_credential

  resources :api_clients, controller: "access_requests", only: %i[index show new create edit update] do
    get :requests_chart, on: :collection
    post :revoke, on: :member
    post :rotate, on: :member
  end
  post "/oauth/token", to: "oauth#token", defaults: { api_key: "public" }
  post "/apis/:api_key/oauth/token", to: "oauth#token", as: :named_api_oauth_token

  namespace :api, defaults: { format: :json, api_key: "public" } do
    namespace :v1, defaults: { api_version: "v1" } do
      get "/", to: "resources#index"
      get "/:resource", to: "resources#index", as: :resource_collection
      post "/:resource", to: "resources#create"
      get "/:resource/:id", to: "resources#show", as: :resource
      patch "/:resource/:id", to: "resources#update"
      delete "/:resource/:id", to: "resources#destroy"
      match "/:resource/:id/:action_name",
        to: "member_actions#create",
        via: %i[post patch put delete],
        constraints: short_action_constraint,
        as: :resource_nested_action
      get "/:resource/:id/:relationship", to: "relationship_resources#index", as: :resource_relationship
      post "/:resource/:id/:relationship", to: "relationship_resources#create"
      patch "/:resource/:id/:relationship/:relationship_id", to: "relationship_resources#update"
      delete "/:resource/:id/:relationship/:relationship_id", to: "relationship_resources#destroy"
      match "/:resource/:id/actions/:action_name",
            to: "member_actions#create",
            via: %i[post patch put delete],
            as: :resource_action
    end

    (RecordingStudioApi.api_versions - ["v1"]).each do |api_version|
      namespace api_version.to_sym, defaults: { api_version: api_version } do
        get "/", to: "/recording_studio_api/api/v1/resources#index"
        get "/:resource", to: "/recording_studio_api/api/v1/resources#index", as: :resource_collection
        post "/:resource", to: "/recording_studio_api/api/v1/resources#create"
        get "/:resource/:id", to: "/recording_studio_api/api/v1/resources#show", as: :resource
        patch "/:resource/:id", to: "/recording_studio_api/api/v1/resources#update"
        delete "/:resource/:id", to: "/recording_studio_api/api/v1/resources#destroy"
        match "/:resource/:id/:action_name",
          to: "/recording_studio_api/api/v1/member_actions#create",
          via: %i[post patch put delete],
          constraints: short_action_constraint,
          as: :resource_nested_action
        get "/:resource/:id/:relationship", to: "/recording_studio_api/api/v1/relationship_resources#index", as: :resource_relationship
        post "/:resource/:id/:relationship", to: "/recording_studio_api/api/v1/relationship_resources#create"
        patch "/:resource/:id/:relationship/:relationship_id", to: "/recording_studio_api/api/v1/relationship_resources#update"
        delete "/:resource/:id/:relationship/:relationship_id", to: "/recording_studio_api/api/v1/relationship_resources#destroy"
        match "/:resource/:id/actions/:action_name",
              to: "/recording_studio_api/api/v1/member_actions#create",
              via: %i[post patch put delete],
              as: :resource_action
      end
    end
  end

  scope "/apis/:api_key/:api_version", defaults: { format: :json }, as: :named_api do
    get "/", to: "api/v1/resources#index", as: :root
    get "/:resource", to: "api/v1/resources#index", as: :resource_collection
    post "/:resource", to: "api/v1/resources#create"
    get "/:resource/:id", to: "api/v1/resources#show", as: :resource
    patch "/:resource/:id", to: "api/v1/resources#update"
    delete "/:resource/:id", to: "api/v1/resources#destroy"
    match "/:resource/:id/:action_name",
          to: "api/v1/member_actions#create",
          via: %i[post patch put delete],
          constraints: short_action_constraint,
          as: :resource_nested_action
    get "/:resource/:id/:relationship", to: "api/v1/relationship_resources#index", as: :resource_relationship
    post "/:resource/:id/:relationship", to: "api/v1/relationship_resources#create"
    patch "/:resource/:id/:relationship/:relationship_id", to: "api/v1/relationship_resources#update"
    delete "/:resource/:id/:relationship/:relationship_id", to: "api/v1/relationship_resources#destroy"
    match "/:resource/:id/actions/:action_name",
          to: "api/v1/member_actions#create",
          via: %i[post patch put delete],
          as: :resource_action
  end
end
