# frozen_string_literal: true

RecordingStudioAccessible.configure do |config|
  # Accessible 0.5+ rejects new grants when this is blank/nil.
  config.access_actor_types = ["User"]
end
