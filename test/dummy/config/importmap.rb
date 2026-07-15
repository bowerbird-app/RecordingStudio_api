# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"

# Pin FlatPack controllers
if defined?(FlatPack::Engine)
	pin_all_from FlatPack::Engine.root.join("app/javascript/flat_pack/controllers"), under: "controllers/flat_pack", to: "flat_pack/controllers"
end

# Pin RecordingStudioAdmin controllers
if defined?(RecordingStudioAdmin::Engine)
  pin_all_from RecordingStudioAdmin::Engine.root.join("app/javascript/recording_studio_admin/controllers"), under: "controllers/recording_studio_admin", to: "recording_studio_admin/controllers", preload: false
end
