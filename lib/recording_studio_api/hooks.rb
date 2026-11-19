# frozen_string_literal: true

module RecordingStudioApi
  module AppliesControllerExtensions
    def extend_controller(controller_name, &block)
      super
      return unless block

      Engine.apply_named_controller_extensions(controller_name)
    end
  end
end
