# frozen_string_literal: true

require_relative "errors"

module RecordingStudioApi
  module InvalidParentInput
    module_function

    def call(message, recordable_type:)
      RecordingStudioApi::InvalidActionInputError.new(
        message,
        details: [
          {
            attribute: :parent_id,
            message: "is not allowed for #{recordable_type}",
            full_message: message,
            type: :invalid
          }
        ]
      )
    end
  end
end
