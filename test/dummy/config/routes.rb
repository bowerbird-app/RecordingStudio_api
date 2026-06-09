Rails.application.routes.draw do
  devise_for :users

  # RecordingStudio engine is data/API-focused and has no browser root route.
  # Keep legacy links working by redirecting the base path to the app home.
  get "/recording_studio", to: redirect("/"), as: nil
  mount RecordingStudio::Engine, at: "/recording_studio"
  mount RecordingStudioAccessible::Engine, at: "/recording_studio_accessible"
  mount RecordingStudioApi::Engine, at: "/recording_studio_api"
  mount RecordingStudioRootSwitchable::Engine, at: "/recording_studio_root_switchable"

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  get "/workspace", to: "home#workspace", as: :workspace
  get "/folder", to: "home#folder", as: :folder
  get "/admin/api", to: "recording_studio_api/admin_dashboards#show", as: :admin_api
  get "/admin/api/logs", to: "recording_studio_api/admin_logs#index", as: :admin_api_logs
  resource :scalar_test_token, only: %i[create destroy]

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  get "docs/install", to: "docs#install", as: :docs_install
  get "docs/config", to: "docs#configuration", as: :docs_config
  get "docs/api_hierarchy", to: "docs#api_hierarchy", as: :docs_api_hierarchy
  get "docs/recordable_types", to: "docs#recordable_types", as: :docs_recordable_types
  get "docs/recordings_tree", to: "docs#recordings_tree", as: :docs_recordings_tree
  get "docs/gem_views", to: "docs#gem_views", as: :docs_gem_views
  get "docs/api_routes", to: "docs#api_routes", as: :docs_api_routes
  get "docs/openapi.json", to: "docs#openapi", as: :docs_openapi
  get "APIdocs", to: redirect("/APIdocs/#{RecordingStudioApi.default_api_version}"), as: :api_docs_root
  get "APIdocs/:version", to: "docs#scalar", as: :api_docs
  get "APIdocs/:version/fullscreen", to: "docs#scalar_fullscreen", as: :api_docs_fullscreen
  get "APIdocs/:version/openapi.json", to: "docs#openapi", as: :api_docs_openapi
  get "docs/scalar", to: "docs#scalar", as: :docs_scalar
  get "docs/scalar/fullscreen", to: "docs#scalar_fullscreen", as: :docs_scalar_fullscreen
  get "docs/add_capability", to: "docs#add_capability", as: :docs_add_capability
  get "docs/auth", to: "docs#auth", as: :docs_auth
  get "docs/methods", to: "docs#methods", as: :docs_methods
  get "docs/versions", to: "docs#versions", as: :docs_versions

  # Defines the root path route ("/")
  root "home#index"
end
