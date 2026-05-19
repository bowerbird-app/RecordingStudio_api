# frozen_string_literal: true

RecordingStudioApi::Engine.routes.draw do
  resources :access_requests, only: %i[index show new create edit update]

  post "/oauth/token", to: "oauth#token"

  namespace :api, defaults: { format: :json } do
    namespace :v1 do
      get "/", to: "resources#index"
      get "/:resource", to: "resources#index", as: :resource_collection
      get "/:resource/:id", to: "resources#show", as: :resource
      get "/:resource/:id/actions", to: "resources#actions", as: :resource_actions
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
