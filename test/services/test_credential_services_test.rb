# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"

class TestCredentialServicesTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user, role: :admin)
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "issues a scoped public test credential with the requested role" do
    result = issue_test_credential(role: :view)

    assert result.success?, result.error
    assert_equal "public", result.value.fetch(:api_client).api_key
    assert_equal "view", result.value.fetch(:role)
    assert_equal "view", result.value.fetch(:access_recording).recordable.role
    assert_match(/\Arsapi_at_/, result.value.fetch(:access_token))
    assert_equal result.value.fetch(:credential), result.value.fetch(:access_token_record).credential
    assert_equal @root_recording, result.value.fetch(:scope_recording)
  end

  test "issues credentials only for the selected named api" do
    RecordingStudioApi.configuration.api(:operations)
    RecordingStudioApi.register_recordable_type_api("Workspace", api: :operations)

    result = issue_test_credential(api: :operations)

    assert result.success?, result.error
    assert_equal "operations", result.value.fetch(:api)
    assert_equal "operations", result.value.fetch(:api_client).api_key

    authentication = RecordingStudioApi::Services::AuthenticateOauthAccessToken.call(
      authorization_header: "Bearer #{result.value.fetch(:access_token)}",
      api: :operations
    )
    assert authentication.success?, authentication.error

    public_authentication = RecordingStudioApi::Services::AuthenticateOauthAccessToken.call(
      authorization_header: "Bearer #{result.value.fetch(:access_token)}",
      api: :public
    )
    assert public_authentication.failure?
  end

  test "rejects invalid roles without creating credentials" do
    assert_no_difference -> { RecordingStudioApi::ApiCredential.count } do
      result = issue_test_credential(role: :owner)

      assert result.failure?
      assert_equal "Access role is invalid", result.error
    end
  end

  test "rejects an actor without RecordingStudioAccessible access to the scope" do
    outsider = create_user(email: "test-credential-outsider@example.com")

    assert_no_difference -> { RecordingStudioApi::ApiClient.count } do
      result = RecordingStudioApi::Services::IssueTestCredential.call(
        api: :public,
        actor: outsider,
        access_point_recording: @root_recording,
        role: :view,
        name: "Unauthorized test credential"
      )

      assert result.failure?
      assert_equal "Not authorized to manage access", result.error
    end
  end

  test "rejects a role stronger than the actor can assign" do
    RecordingStudio::Access.where(id: @access_recording.recordable_id).update_all(role: "edit")
    RecordingStudioApi.configuration.access_management_edit_role = :edit

    assert_no_difference -> { RecordingStudioApi::ApiClient.count } do
      result = issue_test_credential(role: :admin)

      assert result.failure?
      assert_equal "Requested API access role exceeds the manager's access", result.error
    end
  end

  test "rejects protected API issuance without access to its admin section" do
    configure_dummy_operations_api!
    RecordingStudio.enable_capability(:accessible, on: "AdminSection")
    RecordingStudio.enable_capability(:api_access_point, on: "AdminSection")
    RecordingStudioApi.register_recordable_type_api("AdminSection", api: :operations)

    owner = create_user(email: "test-credential-owner@example.com")
    delegated_manager = create_user(email: "test-credential-delegated@example.com")
    _admin_root, admin_root_recording = create_admin_root_recording(name: "Test credential admin")
    with_access_creation_context do
      access = RecordingStudio::Access.create!(actor: owner, role: :admin)
      RecordingStudio::Recording.create!(recordable: access, parent_recording: admin_root_recording)
    end
    admin_section_recording = RecordingStudio::Recording.create!(
      recordable: AdminSection.create!(key: "test_credentials", name: "Test credentials"),
      parent_recording: admin_root_recording
    )
    delegated_access = RecordingStudioAccessible.grant_access(
      recording: admin_section_recording,
      actor: delegated_manager,
      role: :admin,
      manager_actor: owner
    )
    assert delegated_access.success?, delegated_access.error
    RecordingStudioApi::Admin::ApiAuthorization.recording_for(
      api: :operations,
      root_recording: admin_root_recording,
      create: true
    )

    assert_no_difference -> { RecordingStudioApi::ApiClient.count } do
      result = RecordingStudioApi::Services::IssueTestCredential.call(
        api: :operations,
        actor: delegated_manager,
        access_point_recording: admin_section_recording,
        role: :view,
        name: "Unauthorized operations test credential"
      )

      assert result.failure?
      assert_equal "Not authorized to manage the selected API", result.error
    end
  end

  test "revokes only a matching credential and access token pair" do
    first = issue_test_credential.value
    second = issue_test_credential.value

    mismatch = RecordingStudioApi::Services::RevokeTestCredential.call(
      api: :public,
      credential_id: first.fetch(:credential).id,
      access_token_id: second.fetch(:access_token_record).id
    )

    assert mismatch.failure?
    assert_nil first.fetch(:credential).reload.revoked_at
    assert_nil second.fetch(:access_token_record).reload.revoked_at

    result = RecordingStudioApi::Services::RevokeTestCredential.call(
      api: :public,
      credential_id: first.fetch(:credential).id,
      access_token_id: first.fetch(:access_token_record).id
    )

    assert result.success?, result.error
    assert_not_nil first.fetch(:credential).reload.revoked_at
    assert_not_nil first.fetch(:access_token_record).reload.revoked_at
  end

  test "does not revoke a credential through another api" do
    RecordingStudioApi.configuration.api(:operations)
    RecordingStudioApi.register_recordable_type_api("Workspace", api: :operations)
    payload = issue_test_credential(api: :operations).value

    result = RecordingStudioApi::Services::RevokeTestCredential.call(
      api: :public,
      credential_id: payload.fetch(:credential).id,
      access_token_id: payload.fetch(:access_token_record).id
    )

    assert result.failure?
    assert_nil payload.fetch(:credential).reload.revoked_at
    assert_nil payload.fetch(:access_token_record).reload.revoked_at
  end

  private

  def issue_test_credential(api: :public, role: :edit)
    RecordingStudioApi::Services::IssueTestCredential.call(
      api: api,
      actor: @user,
      access_point_recording: @root_recording,
      role: role,
      name: "Generated test credential"
    )
  end
end