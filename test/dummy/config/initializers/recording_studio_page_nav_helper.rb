# frozen_string_literal: true

# Admin engine views render outside the dummy controller that would
# normally pick up app/helpers. Mix the compatibility helper into every
# controller.
Rails.application.config.to_prepare do
  next if ActionController::Base._helpers < RecordingStudioPageNavHelper

  ActionController::Base.helper(RecordingStudioPageNavHelper)
end
