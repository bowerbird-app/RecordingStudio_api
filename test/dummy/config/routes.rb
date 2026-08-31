Rails.application.routes.draw do
  devise_for :users

  # RecordingStudio engine is data/API-focused and has no browser root route.
  # Keep legacy links working by redirecting the base path to the app home.
  get "/recording_studio", to: redirect("/"), as: nil
  mount RecordingStudio::Engine, at: "/recording_studio"
  mount RecordingStudioAccessible::Engine, at: "/recording_studio_accessible"
  mount RecordingStudioApi::Engine, at: "/recording_studio_api"
  mount RecordingStudioRootSwitchable::Engine, at: "/recording_studio_root_switchable"
  mount RecordingStudioAccessible::Engine, at: "/admin/access", as: :recording_studio_admin_access

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  get "/workspace", to: "home#workspace", as: :workspace
  get "/folder", to: "home#folder", as: :folder
  resources :connected_apps, only: %i[index destroy]
  get "/.well-known/oauth-authorization-server", to: "recording_studio_api/oauth_discoveries#authorization_server", defaults: { api_key: "public" }
  get "/.well-known/oauth-protected-resource", to: "recording_studio_api/oauth_discoveries#protected_resource", defaults: { api_key: "public" }
  recording_studio_admin_for :api, at: "/api", root_section: :api
  recording_studio_admin_for :admin_api, at: "/admin/api", root_section: :admin_api
  recording_studio_admin_for :admin_operations_api, at: "/admin/api/operations", root_section: :admin_operations_api

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
  get "APIdocs", to: "recording_studio_api/scalar_docs#redirect_to_default", defaults: { api_key: "public", engine_mount_path: "/recording_studio_api" }, as: :api_docs_root
  get "APIdocs/:version/openapi.json", to: "recording_studio_api/scalar_docs#openapi", defaults: { api_key: "public", engine_mount_path: "/recording_studio_api" }, as: :api_docs_openapi
  get "APIdocs/:version/fullscreen", to: "recording_studio_api/scalar_docs#fullscreen", defaults: { api_key: "public", engine_mount_path: "/recording_studio_api" }, as: :api_docs_fullscreen
  get "APIdocs/:version", to: "recording_studio_api/scalar_docs#show", defaults: { api_key: "public", engine_mount_path: "/recording_studio_api" }, as: :api_docs
  get "docs/scalar/fullscreen", to: redirect("/docs/scalar/#{RecordingStudioApi.default_api_version}/fullscreen"), as: :docs_scalar_fullscreen
  get "docs/add_capability", to: "docs#add_capability", as: :docs_add_capability
  get "docs/auth", to: "docs#auth", as: :docs_auth
  get "docs/methods", to: "docs#methods", as: :docs_methods
  get "docs/versions", to: "docs#versions", as: :docs_versions

  # Defines the root path route ("/")
  root "home#index"
  recording_studio_api_scalar_docs_for :operations,
    at: "/admin/operations-api/docs",
    as: :operations_api_scalar_docs

  recording_studio_api_scalar_docs_for :public,
    at: "/docs/scalar",
    as: :public_api_scalar_docs

# BEGIN RecordingStudioApi test auth routes: public_api
get "/docs/scalar/:version/test-credential", to: "public_api/scalar_test_credentials#show", as: :public_api_scalar_test_credential
post "/docs/scalar/:version/test-credential", to: "public_api/scalar_test_credentials#create"
delete "/docs/scalar/:version/test-credential", to: "public_api/scalar_test_credentials#destroy"
# END RecordingStudioApi test auth routes: public_api

# BEGIN RecordingStudioApi test auth routes: operations_api
get "/admin/operations-api/docs/:version/test-credential", to: "operations_api/scalar_test_credentials#show", as: :operations_api_scalar_test_credential
post "/admin/operations-api/docs/:version/test-credential", to: "operations_api/scalar_test_credentials#create"
delete "/admin/operations-api/docs/:version/test-credential", to: "operations_api/scalar_test_credentials#destroy"
# END RecordingStudioApi test auth routes: operations_api

end
