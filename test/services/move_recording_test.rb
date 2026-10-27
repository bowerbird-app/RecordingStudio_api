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

  test "default move action uses Moveable's handler" do
    action = RecordingStudioApi.capability_action(:move)

    assert_equal RecordingStudio::Moveable::Api::MoveRecording, action.handler
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
      RecordingStudio::Moveable::Api::MoveRecording.call(context)
    end

    assert_equal "Destination recording was not found in this API scope", error.message
  end

  test "moves a folder under another accessible folder in the same root" do
    source_page = create_page_recording(root_recording: @root_recording)
    source_folder = source_page.parent_recording
    destination_page = create_page_recording(root_recording: @root_recording)
    destination_folder = destination_page.parent_recording

    context = RecordingStudioApi::ActionContext.new(
      recording: source_folder,
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
      params: { parent_id: destination_folder.id }
    )

    moved = RecordingStudio::Moveable::Api::MoveRecording.call(context)

    assert_equal source_folder.id, moved.id
    assert_equal destination_folder.id, source_folder.reload.parent_recording_id
  end
end
