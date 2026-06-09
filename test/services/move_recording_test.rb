# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"

class MoveRecordingTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  StubRecording = Class.new do
    def move_to!(**); end

    def reload
      self
    end
  end

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user, role: :edit)
    @payload = provision_api_client_for(access_recording: @access_recording, name: "Move token")
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "rejects a destination outside the authenticated root scope" do
    other_root_recording, = create_access_recording_for(user: create_user(email: "move-other-root@example.com"))
    hidden_page = create_page_recording(root_recording: other_root_recording)

    context = RecordingStudioApi::ActionContext.new(
      recording: StubRecording.new,
      api_client: @payload.fetch(:api_client),
      credential: @payload.fetch(:credential),
      access_recording: @access_recording,
      access_grant: RecordingStudioApi::AccessGrant.new(
        api_client: @payload.fetch(:api_client),
        credential: @payload.fetch(:credential),
        access_recording: @access_recording,
        root_recording: @root_recording
      ),
      root_recording: @root_recording,
      params: { destination_id: hidden_page.parent_recording_id }
    )

    error = assert_raises(RecordingStudioApi::NotFoundError) do
      RecordingStudioApi::Services::MoveRecording.call(context)
    end

    assert_equal "Destination recording was not found in this API scope", error.message
  end
end
