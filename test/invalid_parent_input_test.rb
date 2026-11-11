# frozen_string_literal: true

require "test_helper"

class InvalidParentInputTest < Minitest::Test
  def test_builds_invalid_action_input_with_parent_id_detail
    error = RecordingStudioApi::InvalidParentInput.call(
      "Folder cannot be recorded under Page",
      recordable_type: "Folder"
    )

    assert_instance_of RecordingStudioApi::InvalidActionInputError, error
    assert_equal "Folder cannot be recorded under Page", error.message
    assert_equal [
      {
        attribute: :parent_id,
        message: "is not allowed for Folder",
        full_message: "Folder cannot be recorded under Page",
        type: :invalid
      }
    ], error.details
  end
end
