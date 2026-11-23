# frozen_string_literal: true

require_relative "support/api_dummy_helpers"

class ScopedRecordingTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    @user = create_user
    @root, @access = create_access_recording_for(user: @user, role: :edit)
    @page = create_page_recording(root_recording: @root)
    @folder = @page.parent_recording
    @grant = RecordingStudioApi::AccessGrant.new(
      api_client: nil,
      credential: nil,
      access_recording: @access,
      root_recording: @root
    )
  end

  teardown do
    reset_recording_studio_api_configuration!
    Current.actor = nil if defined?(Current)
  end

  test "find! names the expected and actual public types on a type mismatch" do
    error = assert_raises(RecordingStudioApi::NotFoundError) do
      RecordingStudioApi::ScopedRecording.find!(
        access_grant: @grant,
        id: @folder.id,
        recordable_type: "Page"
      )
    end

    assert_equal expected_mismatch("Page", "Folder"), error.message
  end

  test "find! falls back to the class name when the type is unregistered" do
    error = assert_raises(RecordingStudioApi::NotFoundError) do
      RecordingStudioApi::ScopedRecording.find!(
        access_grant: @grant,
        id: @page.id,
        recordable_type: "Addon::UnregisteredKit"
      )
    end

    assert_nil RecordingStudioApi.recordable_registration_for("Addon::UnregisteredKit")
    assert_equal expected_mismatch("Addon::UnregisteredKit", "Page"), error.message
  end

  test "find! keeps a custom type_mismatch string" do
    error = assert_raises(RecordingStudioApi::NotFoundError) do
      RecordingStudioApi::ScopedRecording.find!(
        access_grant: @grant,
        id: @folder.id,
        recordable_type: "Page",
        type_mismatch: "Parent resource type does not match Page"
      )
    end

    assert_equal "Parent resource type does not match Page", error.message
  end

  test "find! still uses the missing message when the id is out of scope" do
    foreign_root, = create_access_recording_for(user: create_user, workspace_name: "Foreign #{SecureRandom.hex(4)}")
    foreign_page = create_page_recording(root_recording: foreign_root)

    error = assert_raises(RecordingStudioApi::NotFoundError) do
      RecordingStudioApi::ScopedRecording.find!(
        access_grant: @grant,
        id: foreign_page.id,
        recordable_type: "Page"
      )
    end

    assert_equal "Resource was not found in this API scope", error.message
  end

  private

  def expected_mismatch(expected, actual)
    "Expected a #{expected}, but this id is a #{actual}. Pass the id of a #{expected} recording (the id returned when that resource was created or looked up)."
  end
end
