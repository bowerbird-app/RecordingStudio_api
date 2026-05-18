# frozen_string_literal: true

RecordingStudioApi::Engine.routes.draw do
  namespace :api, defaults: { format: :json } do
    namespace :v1 do
      get "/", to: "resources#index"
      get "/:resource", to: "resources#index", as: :resource_collection
      get "/:resource/:id", to: "resources#show", as: :resource
      get "/:resource/:id/actions", to: "resources#actions", as: :resource_actions
      match "/:resource/:id/actions/:action_name",
            to: "member_actions#create",
            via: %i[get post patch put delete],
            as: :resource_action
    end
  end
end
