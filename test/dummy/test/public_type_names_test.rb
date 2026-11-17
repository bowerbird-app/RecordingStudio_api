# frozen_string_literal: true

require "test_helper"

class PublicTypeNamesTest < ActiveSupport::TestCase
  test "dummy registrations expose demodulized public names" do
    assert_equal "Workspace", RecordingStudioApi.public_name_for("Workspace")
    assert_equal "Folder", RecordingStudioApi.public_name_for("Folder")
    assert_includes RecordingStudioApi.public_type_names, "Workspace"
    assert_equal "Workspace", RecordingStudioApi.recordable_type_for_public_name("Workspace")
  end
end
