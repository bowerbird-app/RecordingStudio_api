# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"

class ResourceOperationsWriteActorTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user, role: :edit)
    @folder = create_page_recording(root_recording: @root_recording).parent_recording
    install_accessible_edit_write_policy!
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "an editor can update through the API when the app has no access grants" do
    api_client = ungranted_api_client
    result = RecordingStudioApi::Services::ResourceOperations::Update.call(
      resource_context_for(
        access_recording: @access_recording,
        api_client: api_client,
        folder: @folder,
        name: "Edited as the signed-in user"
      )
    )

    assert_equal :ok, result.fetch(:status, :ok)
    assert_equal "Edited as the signed-in user", @folder.reload.recordable.name
    event = latest_update_event(@folder)
    assert_equal @user, event.actor
    assert_equal api_client, event.impersonator
  end

  test "a view-only user is still denied" do
    view_user = create_user(email: "view-only-write-actor@example.com")
    view_root, view_access = create_access_recording_for(user: view_user, role: :view)
    folder = create_page_recording(root_recording: view_root).parent_recording
    install_accessible_edit_write_policy!

    error = assert_raises(RecordingStudioApi::AuthorizationError) do
      RecordingStudioApi::Services::ResourceOperations::Update.call(
        resource_context_for(
          access_recording: view_access,
          api_client: ungranted_api_client,
          folder: folder,
          name: "Blocked for a viewer"
        )
      )
    end

    assert_equal "API access grant is not authorized for this capability", error.message
    assert_not_equal "Blocked for a viewer", folder.reload.recordable.name
    assert_nil latest_update_event(folder)
  end

  test "a client-credentials grant with no user still writes as the API client" do
    payload = provision_api_client_for(access_recording: @access_recording, name: "Machine writer")
    api_client = payload.fetch(:api_client)

    result = RecordingStudioApi::Services::ResourceOperations::Update.call(
      resource_context_for(
        access_recording: payload.fetch(:access_recording),
        api_client: api_client,
        folder: @folder,
        name: "Edited by the machine client"
      )
    )

    assert_equal :ok, result.fetch(:status, :ok)
    event = latest_update_event(@folder)
    assert_equal api_client, event.actor
    assert_nil event.impersonator_id
    assert_nil event.impersonator_type
  end

  private

  def install_accessible_edit_write_policy!
    RecordingStudio.configuration.authorize_write = method(:accessible_edit_write_allowed?)
  end

  def accessible_edit_write_allowed?(actor:, action:, recording: nil, root_recording: nil, **)
    return false unless actor.is_a?(ActiveRecord::Base) && action.to_s.strip.present?

    target = recording || root_recording
    return false if target.nil?

    RecordingStudioAccessible.authorized?(actor: actor, recording: target, role: :edit)
  end

  def ungranted_api_client
    RecordingStudioApi::ApiClient.create!(name: "App without grants", api_key: "public")
  end

  def resource_context_for(access_recording:, api_client:, folder:, name:)
    grant = RecordingStudioApi::AccessGrant.new(
      api_client: api_client,
      credential: nil,
      access_recording: access_recording,
      root_recording: access_recording.root_recording || @root_recording
    )
    RecordingStudioApi::ResourceOperationContext.new(
      recording: folder,
      recordable_type: "Folder",
      resource_name: "folders",
      api_client: api_client,
      credential: nil,
      access_recording: access_recording,
      access_grant: grant,
      root_recording: grant.root_recording,
      api_version: "v1",
      params: {},
      request_params: { "name" => name },
      scoped_recordings: grant.accessible_recordings,
      parent_recording: nil
    )
  end

  def latest_update_event(recording)
    RecordingStudio::Event.where(recording_id: recording.id, action: "updated").order(occurred_at: :desc, created_at: :desc).first
  end
end
