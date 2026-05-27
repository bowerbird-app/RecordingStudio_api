# frozen_string_literal: true

RecordingStudioRootSwitchable.configure do |config|
  config.current_actor_resolver = lambda do |controller:|
    Current.actor || controller.current_user
  end

  config.layout = :application_layout

  # For production hosts, enable secure cookies and force SSL in the host app.
  # config.device_key_cookie_options = config.device_key_cookie_options.merge(secure: Rails.env.production?)

  config.after_switch_redirect = lambda do |controller:, return_to:, root_recording:, **|
    requested_return_to = return_to.presence
    return controller.main_app.root_path if requested_return_to.blank?

    requested_return_to
  end

  config.scope :all_roots do |scope|
    scope.label = "All roots"
    scope.description = "Admin and standard roots available to the current actor"
    scope.available_roots = lambda do |actor:, **|
      RecordingStudioAccessible.root_recordings_for(actor: actor, minimum_role: :view)
    end
    scope.default_root = lambda do |roots:, **|
      roots.find { |recording| recording.recordable.is_a?(RecordingStudioAdmin::Admin) } || roots.first
    end
  end
end
