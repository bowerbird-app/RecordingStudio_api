# frozen_string_literal: true

RecordingStudioAccessible.configure do |config|
  # Accessible 0.5+ rejects new grants when this is blank/nil.
  # API client provisioning grants Access recordings to ApiClient actors.
  config.access_actor_types = ["User", "RecordingStudioApi::ApiClient"]
end
