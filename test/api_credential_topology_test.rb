# frozen_string_literal: true

require_relative "support/api_dummy_helpers"

class ApiCredentialTopologyTest < ActiveSupport::TestCase
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

  test "a credential is accepted when the access grant actor is the client" do
    payload = provision_api_client_for(access_recording: @access_recording, name: "Granted client")
    client = payload.fetch(:api_client)
    access = payload.fetch(:access_recording)

    assert_equal client, access.recordable.actor
    payload.fetch(:credential).revoke!

    replacement = credential_for(client)

    assert_nil replacement.revoked_at
    assert_equal access.id, client.access_recording.id
  end

  test "a second client under someone else's grant cannot take a credential" do
    payload = provision_api_client_for(access_recording: @access_recording, name: "Grant owner")
    access = payload.fetch(:access_recording)
    other = RecordingStudioApi::ApiClient.create!(name: "Other client #{SecureRandom.hex(4)}")
    RecordingStudio.record!(
      action: "created",
      recordable: other,
      parent_recording: access,
      root_recording: access.root_recording,
      actor: other
    )

    error = assert_raises(ActiveRecord::RecordInvalid) { credential_for(other) }

    assert_includes error.message, "must sit under an access grant for this API client"
    assert_equal payload.fetch(:api_client), access.reload.recordable.actor
  end

  test "one client keeps a single credential with revoked_at nil" do
    payload = provision_api_client_for(access_recording: @access_recording, name: "Indexed client")
    client = payload.fetch(:api_client)

    assert_raises(ActiveRecord::RecordNotUnique) { credential_for(client) }
    assert_equal 1, client.credentials.where(revoked_at: nil).count
  end

  private

  def credential_for(client)
    RecordingStudioApi::ApiCredential.create!(
      api_client: client,
      token_public_id: "pub_#{SecureRandom.hex(8)}",
      token_digest: "digest_#{SecureRandom.hex(16)}",
      token_prefix: "api",
      expires_at: 7.days.from_now
    )
  end
end
