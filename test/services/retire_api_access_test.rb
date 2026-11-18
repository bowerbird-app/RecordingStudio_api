# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"

class RetireApiAccessTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user)
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "trashing keeps the subtree rows and writes trashed events" do
    payload = provision_api_client_for(access_recording: @access_recording, name: "Retiring key")
    client = payload.fetch(:api_client)
    credential = payload.fetch(:credential)
    access = payload.fetch(:access_recording)
    token = RecordingStudioApi::ApiAccessToken.create!(
      credential: credential,
      token_digest: "digest_#{SecureRandom.hex(16)}",
      token_prefix: "atk",
      expires_at: 1.hour.from_now
    )
    token_recording = RecordingStudio.record!(
      action: "created",
      recordable: token,
      parent_recording: credential.recording,
      root_recording: credential.recording.root_recording,
      actor: client
    ).recording

    result = RecordingStudioApi::Services::RetireApiAccess.call(access_recording: access, actor: @user)

    assert result.success?, result.error
    access.reload
    assert_nil access.trashed_at
    client_recording = RecordingStudio::Recording.unscoped.find_by!(recordable: client)
    credential_recording = RecordingStudio::Recording.unscoped.find_by!(recordable: credential)
    assert_predicate client_recording.trashed_at, :present?
    assert client_recording.trash_root
    assert_equal @user, client_recording.events(actions: "trashed").first.actor
    assert_predicate credential_recording.trashed_at, :present?
    refute credential_recording.trash_root
    assert_predicate token_recording.reload.trashed_at, :present?
    assert_equal "trashed", client_recording.events(actions: "trashed").first.action
    assert RecordingStudioApi::ApiClient.exists?(client.id)
    assert RecordingStudioApi::ApiCredential.exists?(credential.id)
    assert RecordingStudioApi::ApiAccessToken.exists?(token.id)
    assert RecordingStudio::Access.exists?(access.recordable_id)
    assert_nil credential.reload.revoked_at
    assert_includes RecordingStudioAccessible.access_grants_for(actor: client).pluck(:id), access.id

    revoked = RecordingStudioAccessible.revoke_access(
      recording: access.parent_recording,
      access_recording: access,
      manager_actor: @user
    )

    assert revoked.failure?
    assert_nil access.reload.trashed_at
    assert RecordingStudio::Recording.unscoped.exists?(access.id)
  end

  test "leaves the last admin grant in place" do
    client = RecordingStudioApi::ApiClient.create!(name: "Only admin #{SecureRandom.hex(4)}")
    root = RecordingStudio::Recording.create!(recordable: Workspace.create!(name: "Last admin #{SecureRandom.hex(4)}"))
    bootstrap = RecordingStudioAccessible.bootstrap_owner_access!(recording: root, actor: client)
    assert bootstrap.success?, bootstrap.error

    access = bootstrap.value
    RecordingStudio.record!(
      action: "created",
      recordable: client,
      parent_recording: access,
      root_recording: root,
      actor: client
    )

    result = RecordingStudioApi::Services::RetireApiAccess.call(access_recording: access, actor: client)

    assert result.success?, result.error
    assert_nil access.reload.trashed_at
    assert_predicate RecordingStudio::Recording.unscoped.find_by!(recordable: client).trashed_at, :present?
    assert_includes RecordingStudioAccessible.access_grants_for(actor: client).pluck(:id), access.id
  end
end
