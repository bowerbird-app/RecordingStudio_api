# frozen_string_literal: true

module RecordingStudioAuthorizedWrites
  module_function

  def install!
    RecordingStudio.configuration.authorize_write = method(:allow?)
  end

  def allow?(actor:, action:, **)
    actor.is_a?(ActiveRecord::Base) && action.to_s.strip.present?
  end
end
