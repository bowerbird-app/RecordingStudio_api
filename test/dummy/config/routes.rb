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
  get "APIdocs", to: redirect("/APIdocs/#{RecordingStudioApi.default_api_version}"), as: :api_docs_root
  get "APIdocs/:version", to: "public_api/scalar_docs#show", as: :api_docs
  get "APIdocs/:version/fullscreen", to: "public_api/scalar_docs#fullscreen", as: :api_docs_fullscreen
  get "APIdocs/:version/openapi.json", to: "public_api/scalar_docs#openapi", as: :api_docs_openapi
  get "docs/scalar/fullscreen", to: redirect("/docs/scalar/#{RecordingStudioApi.default_api_version}/fullscreen"), as: :docs_scalar_fullscreen
  get "docs/add_capability", to: "docs#add_capability", as: :docs_add_capability
  get "docs/auth", to: "docs#auth", as: :docs_auth
  get "docs/methods", to: "docs#methods", as: :docs_methods
  get "docs/versions", to: "docs#versions", as: :docs_versions

  # Defines the root path route ("/")
  root "home#index"
# BEGIN RecordingStudioApi Scalar docs: operations_api
get "/admin/operations-api/docs", to: redirect("/admin/operations-api/docs/v1"), as: :operations_api_scalar_docs
get "/admin/operations-api/docs/:version/openapi.json", to: "operations_api/scalar_docs#openapi", as: :operations_api_scalar_docs_openapi
get "/admin/operations-api/docs/:version/fullscreen", to: "operations_api/scalar_docs#fullscreen", as: :operations_api_scalar_docs_fullscreen
get "/admin/operations-api/docs/:version", to: "operations_api/scalar_docs#show", as: :operations_api_scalar_docs_version
# END RecordingStudioApi Scalar docs: operations_api

# BEGIN RecordingStudioApi Scalar docs: public_api
get "/docs/scalar", to: redirect("/docs/scalar/v1"), as: :public_api_scalar_docs
get "/docs/scalar/:version/openapi.json", to: "public_api/scalar_docs#openapi", as: :public_api_scalar_docs_openapi
get "/docs/scalar/:version/fullscreen", to: "public_api/scalar_docs#fullscreen", as: :public_api_scalar_docs_fullscreen
get "/docs/scalar/:version", to: "public_api/scalar_docs#show", as: :public_api_scalar_docs_version
# END RecordingStudioApi Scalar docs: public_api

# BEGIN RecordingStudioApi test auth routes: public_api
post "/docs/scalar/:version/test-credential", to: "public_api/scalar_test_credentials#create", as: :public_api_scalar_test_credential
delete "/docs/scalar/:version/test-credential", to: "public_api/scalar_test_credentials#destroy"
# END RecordingStudioApi test auth routes: public_api

end
