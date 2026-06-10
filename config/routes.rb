# frozen_string_literal: true

RecordingStudioApi::Engine.routes.draw do
  get "/admin_api", to: "admin_dashboards#show", as: :admin_dashboard
  get "/admin_api/settings", to: "admin_settings#show", as: :admin_settings
  get "/admin_api/rate_limiting", to: "admin_rate_limitings#show", as: :admin_rate_limiting
  get "/admin_api/requests", to: "admin_requests#index", as: :admin_requests
  get "/admin_api/logs", to: "admin_logs#index", as: :admin_logs

  resources :api_clients, controller: "access_requests", only: %i[index show new create edit update] do
    get :requests_chart, on: :collection
    get :log, on: :member
    post :revoke, on: :member
    post :rotate, on: :member

    resources :api_access_tokens, path: "tokens", only: :index do
      post :revoke, on: :member
    end
  end
  post "/oauth/token", to: "oauth#token"

  namespace :api, defaults: { format: :json } do
    namespace :v1 do
      get "/", to: "resources#index"
      get "/trash", to: "resources#trash_index", as: :trash_collection
      get "/trash/:id", to: "resources#trash_show", as: :trash
      post "/trash/:id/restore", to: "resources#trash_restore", as: :trash_restore
      delete "/trash/:id", to: "resources#trash_destroy", as: :trash_destroy
      get "/:resource", to: "resources#index", as: :resource_collection
      post "/:resource", to: "resources#create"
      get "/:resource/:id", to: "resources#show", as: :resource
      patch "/:resource/:id", to: "resources#update"
      delete "/:resource/:id", to: "resources#destroy"
      match "/:resource/:id/:action_name",
        to: "member_actions#create",
        via: %i[post patch put delete],
        as: :resource_nested_action
      match "/:resource/:id/actions/:action_name",
            to: "member_actions#create",
            via: %i[post patch put delete],
            as: :resource_action
    end

    (RecordingStudioApi.api_versions - ["v1"]).each do |api_version|
      namespace api_version.to_sym do
        get "/", to: "/recording_studio_api/api/v1/resources#index"
        get "/trash", to: "/recording_studio_api/api/v1/resources#trash_index", as: :trash_collection
        get "/trash/:id", to: "/recording_studio_api/api/v1/resources#trash_show", as: :trash
        post "/trash/:id/restore", to: "/recording_studio_api/api/v1/resources#trash_restore", as: :trash_restore
        delete "/trash/:id", to: "/recording_studio_api/api/v1/resources#trash_destroy", as: :trash_destroy
        get "/:resource", to: "/recording_studio_api/api/v1/resources#index", as: :resource_collection
        post "/:resource", to: "/recording_studio_api/api/v1/resources#create"
        get "/:resource/:id", to: "/recording_studio_api/api/v1/resources#show", as: :resource
        patch "/:resource/:id", to: "/recording_studio_api/api/v1/resources#update"
        delete "/:resource/:id", to: "/recording_studio_api/api/v1/resources#destroy"
        match "/:resource/:id/:action_name",
          to: "/recording_studio_api/api/v1/member_actions#create",
          via: %i[post patch put delete],
          as: :resource_nested_action
        match "/:resource/:id/actions/:action_name",
              to: "/recording_studio_api/api/v1/member_actions#create",
              via: %i[post patch put delete],
              as: :resource_action
      end
    end
  end
end
