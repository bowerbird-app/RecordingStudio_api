# frozen_string_literal: true

RecordingStudioApi::Engine.routes.draw do
  get "/admin_api", to: "admin_dashboards#show", as: :admin_dashboard
  get "/admin_api/logs", to: "admin_logs#index", as: :admin_logs

  resources :api_clients, controller: "access_requests", only: %i[index show new create edit update] do
    resources :api_access_tokens, path: "tokens", only: :index do
      post :revoke, on: :member
    end
  end
  resources :oauth_grant_sessions, only: :index do
    post :revoke, on: :member
  end

  get "/oauth/authorize", to: "oauth_authorizations#new"
  post "/oauth/token", to: "oauth#token"
  post "/oauth/revoke", to: "oauth#revoke"

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
  end
end
