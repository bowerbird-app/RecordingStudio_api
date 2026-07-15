# frozen_string_literal: true

RecordingStudioRootSwitchable.configure do |config|
  config.current_actor_resolver = lambda do |controller:|
    Current.actor || controller.current_user
  end

  config.layout = "recording_studio/default_layout"

  # For production hosts, enable secure cookies and force SSL in the host app.
  # config.device_key_cookie_options = config.device_key_cookie_options.merge(secure: Rails.env.production?)

  config.after_switch_redirect = lambda do |controller:, return_to:, root_recording:, **|
    requested_return_to = return_to.presence
    return controller.main_app.root_path if requested_return_to.blank?

    root_switch_path = URI.parse(
      controller.recording_studio_root_switchable.root_switch_path(scope: "all_roots")
    ).path
    resolved_return_to = requested_return_to

    loop do
      parsed_return_to = URI.parse(resolved_return_to)
      break unless parsed_return_to.path == root_switch_path

      nested_return_to = Rack::Utils.parse_nested_query(parsed_return_to.query)["return_to"].presence
      break if nested_return_to.blank?

      resolved_return_to = nested_return_to
    rescue URI::InvalidURIError
      break
    end

    resolved_return_to_path = URI.parse(resolved_return_to).path
    non_admin_root = root_recording.recordable_type != "AdminRoot"

    if non_admin_root && resolved_return_to_path.start_with?("/admin")
      controller.main_app.root_path
    else
      resolved_return_to
    end
  rescue URI::InvalidURIError
    controller.main_app.root_path
  end

  config.scope :all_roots do |scope|
    scope.label = "All roots"
    scope.description = "Admin and standard roots available to the current actor"
    scope.available_roots = lambda do |actor:, **|
      RecordingStudioAccessible.root_recordings_for(actor: actor, minimum_role: :view)
    end
    scope.default_root = lambda do |roots:, **|
      roots.find { |recording| recording.recordable_type == "AdminRoot" } || roots.first
    end
  end
end
