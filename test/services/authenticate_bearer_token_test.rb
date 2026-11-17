# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"

class AuthenticateBearerTokenTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user)
    @payload = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: @access_recording,
      name: "Primary token"
    ).value
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "authenticates a bearer token while the credential recording is kept" do
    credential = @payload.fetch(:credential)

    assert_predicate credential.recording, :kept?
    assert_predicate credential, :active_for_authentication?

    result = RecordingStudioApi::Services::AuthenticateBearerToken.call(
      authorization_header: "Bearer #{@payload.fetch(:token)}"
    )

    assert result.success?, result.error
    assert_equal credential.id, result.value.credential.id
  end

  test "rejects a bearer token when only the credential recording is trashed" do
    credential = @payload.fetch(:credential)
    access_recording = credential.effective_access_recording
    client_recording = credential.api_client.recording
    credential_recording = credential.recording

    RecordingStudio.enable_capability(:trashable, on: credential_recording.recordable_type)
    credential_recording.recording_studio_trashable_trash!(actor: @user)
    credential.instance_variable_set(:@recording, nil)

    assert_nil credential.revoked_at
    refute_predicate credential, :expired?
    assert_predicate access_recording.reload, :kept?
    assert_predicate client_recording.reload, :kept?
    refute_equal credential_recording.id, access_recording.id
    refute_equal credential_recording.id, client_recording.id
    refute_predicate credential.recording, :kept?
    refute_predicate credential, :active_for_authentication?

    result = RecordingStudioApi::Services::AuthenticateBearerToken.call(
      authorization_header: "Bearer #{@payload.fetch(:token)}"
    )

    assert result.failure?
    assert_equal "Bearer token is inactive", result.error
    assert_nil credential.reload.last_used_at
  end

  test "authenticates a valid bearer token" do
    result = RecordingStudioApi::Services::AuthenticateBearerToken.call(
      authorization_header: "Bearer #{@payload.fetch(:token)}"
    )

    assert result.success?, result.error
    assert_equal @payload.fetch(:api_client).id, result.value.api_client.id
    assert_equal @payload.fetch(:credential).id, result.value.credential.id
    assert_equal @payload.fetch(:access_recording).id, result.value.access_recording.id
    assert_equal @root_recording.id, result.value.root_recording.id
  end

  test "rejects a revoked bearer token" do
    @payload.fetch(:credential).revoke!

    result = RecordingStudioApi::Services::AuthenticateBearerToken.call(
      authorization_header: "Bearer #{@payload.fetch(:token)}"
    )

    assert result.failure?
    assert_equal "Bearer token is inactive", result.error
  end

  test "resolves the workspace root for a key on a folder" do
    folder = nested_folder_recording("Token folder", @root_recording)
    payload = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_point_recording: folder,
      manager_actor: @user,
      role: :admin,
      name: "Folder token"
    ).value
    access_recording = payload.fetch(:access_recording)

    result = RecordingStudioApi::Services::AuthenticateBearerToken.call(
      authorization_header: "Bearer #{payload.fetch(:token)}"
    )

    assert result.success?, result.error.to_s
    assert_equal @root_recording.id, result.value.root_recording.id
    assert_equal RecordingStudio.root_recording_id_for(access_recording), result.value.root_recording.id
  end

  test "rejects a token when its root recording is trashed" do
    user = create_user(email: "scoped-auth@example.com")
    root_recording, access_recording = create_access_recording_for(user: user)
    payload = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: access_recording,
      name: "Scoped token"
    ).value

    root_recording.update!(trashed_at: Time.current)

    result = RecordingStudioApi::Services::AuthenticateBearerToken.call(
      authorization_header: "Bearer #{payload.fetch(:token)}"
    )

    assert result.failure?
    assert_equal "Bearer token scope is invalid", result.error
  end
end
