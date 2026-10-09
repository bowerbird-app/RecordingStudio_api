# frozen_string_literal: true

require "test_helper"

class UiMetadataTest < ActiveSupport::TestCase
  test "dummy registrations have no ui and lookups stay empty" do
    assert_nil RecordingStudioApi.ui_for(:ping)
    assert_nil RecordingStudioApi.ui_for(:move)
    assert_empty RecordingStudioApi.actions_for_ui("presskits.editor")
  end
end
