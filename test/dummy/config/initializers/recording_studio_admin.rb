# frozen_string_literal: true

RecordingStudioAdmin.configure do |config|
  config.current_actor_resolver = lambda do |controller:|
    current_actor = defined?(Current) && Current.respond_to?(:actor) ? Current.actor : nil
    current_actor || controller.try(:current_user)
  end

  config.current_root_recording_resolver = lambda do |controller:, **|
    controller.current_root_recording
  end
end
