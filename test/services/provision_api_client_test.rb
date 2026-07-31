# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"

class ProvisionApiClientTest < ActiveSupport::TestCase
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

  test "provisions an api client beneath its own access recording" do
    result = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: @access_recording,
      name: "Primary token"
    )

    assert result.success?, result.error

    payload = result.value
    parsed_token = RecordingStudioApi::Token.parse(payload.fetch(:token))
    client_access_recording = payload.fetch(:access_recording)

    refute_equal @access_recording.id, client_access_recording.id
    assert_equal @root_recording.id, client_access_recording.parent_recording_id
    assert_equal payload.fetch(:api_client), client_access_recording.recordable.actor
    assert_equal client_access_recording.id, payload.fetch(:api_client).access_recording_id
    assert_equal client_access_recording.id, payload.fetch(:recording).parent_recording_id
    assert_equal payload.fetch(:api_client).id, payload.fetch(:credential).api_client_id
    assert_equal client_access_recording.id, payload.fetch(:credential).effective_access_recording_id
    assert_equal payload.fetch(:recording).id, payload.fetch(:credential).recording.parent_recording_id
    assert_equal "RecordingStudioApi::ApiCredential", payload.fetch(:credential).recording.recordable_type
    assert_equal parsed_token.fetch(:public_id), payload.fetch(:credential).token_public_id
    assert_not_equal payload.fetch(:token), payload.fetch(:credential).token_digest
  end

  test "assigns a provisioned client to the selected api" do
    RecordingStudioApi.configuration.api(:operations)
    RecordingStudioApi.register_recordable_type_api("Workspace", api: :operations)

    result = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: @access_recording,
      name: "Operations agent",
      api: :operations
    )

    assert result.success?, result.error
    assert_equal "operations", result.value.fetch(:api_client).api_key
  end

  test "rejects direct provisioning for an access point outside the selected api" do
    RecordingStudioApi.configuration.api(:operations)
    RecordingStudioApi.register_recordable_type_api("AdminRoot", api: :operations)

    result = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: @access_recording,
      name: "Invalid operations agent",
      api: :operations
    )

    assert result.failure?
    assert_equal "Access point recording does not allow API access", result.error
  end

  test "rejects protected api provisioning without api management access" do
    RecordingStudioApi.configuration.api(:operations) do |api|
      api.api_management_authorization_required = true
    end
    RecordingStudio.enable_capability(:accessible, on: "AdminSection")
    RecordingStudio.enable_capability(:api_access_point, on: "AdminSection")
    RecordingStudioApi.register_recordable_type_api("AdminSection", api: :operations)
    _admin_root, admin_root_recording = create_admin_root_recording(name: "Protected API admin")
    with_access_creation_context do
      root_access = RecordingStudio::Access.create!(actor: @user, role: :admin)
      RecordingStudio::Recording.create!(recordable: root_access, parent_recording: admin_root_recording)
    end
    admin_section_recording = RecordingStudio::Recording.create!(
      recordable: AdminSection.create!(key: "delegated_api_access", name: "Delegated API access"),
      parent_recording: admin_root_recording
    )
    delegated_manager = create_user(email: "delegated-api-manager@example.com")
    grant_result = RecordingStudioAccessible.grant_access(
      recording: admin_section_recording,
      actor: delegated_manager,
      role: :admin,
      manager_actor: @user
    )

    assert grant_result.success?, grant_result.error
    assert RecordingStudioApi::AccessManagementPolicy.new(actor: delegated_manager).can_manage_recording?(admin_section_recording)

    assert_no_difference -> { RecordingStudioApi::ApiClient.count } do
      result = RecordingStudioApi::Services::ProvisionApiClient.call(
        access_point_recording: admin_section_recording,
        manager_actor: delegated_manager,
        role: :admin,
        name: "Forged operations agent",
        api: :operations
      )

      assert result.failure?
      assert_equal "Not authorized to manage the selected API", result.error
    end
  end

  test "does not allow an existing client audience to change" do
    payload = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: @access_recording,
      name: "Audience-bound client"
    ).value
    client = payload.fetch(:api_client)

    RecordingStudioApi.configuration.api(:operations)
    client.api_key = "operations"

    refute client.save
    assert_includes client.errors[:api_key], "cannot be changed"
    assert_equal "public", client.reload.api_key
  end

  test "keeps existing client credentials active when provisioning another client for the same access" do
    first = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: @access_recording,
      name: "First token"
    ).value

    second_result = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: @access_recording,
      name: "Second token"
    )

    assert second_result.success?, second_result.error

    refute_equal first.fetch(:api_client).id, second_result.value.fetch(:api_client).id
    refute_equal first.fetch(:access_recording).id, second_result.value.fetch(:access_recording).id
    assert_nil first.fetch(:credential).reload.revoked_at
    assert_nil second_result.value.fetch(:credential).reload.revoked_at
  end

  test "accessible grants upsert duplicate direct access for the same actor and recording" do
    target_user = create_user(email: "duplicate-access-target@example.com")

    first_result = RecordingStudioAccessible.grant_access(
      recording: @root_recording,
      actor: target_user,
      role: :view,
      manager_actor: @user
    )

    assert first_result.success?, first_result.error

    second_result = RecordingStudioAccessible.grant_access(
      recording: @root_recording,
      actor: target_user,
      role: :admin,
      manager_actor: @user
    )

    assert second_result.success?, second_result.error
    assert_equal first_result.value.id, second_result.value.id
    assert_equal "admin", second_result.value.reload.recordable.role
    assert_equal 1, RecordingStudioAccessible.access_recordings_for_actor(
      recording: @root_recording,
      actor: target_user
    ).count
  end

  test "rejects direct provisioning when the manager cannot manage access" do
    view_user = create_user(email: "view-direct-provision@example.com")
    _view_root_recording, view_access_recording = create_access_recording_for(user: view_user, role: :view)

    result = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: view_access_recording,
      name: "Blocked direct token"
    )

    assert result.failure?
    assert_equal "Not authorized to manage access", result.error
  end

  test "prevents direct provisioning above the manager's effective role" do
    edit_user = create_user(email: "edit-direct-provision@example.com")
    _edit_root_recording, edit_access_recording = create_access_recording_for(user: edit_user, role: :edit)
    RecordingStudioApi.configuration.access_management_edit_role = :edit

    result = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: edit_access_recording,
      role: :admin,
      name: "Escalated direct token"
    )

    assert result.failure?
    assert_equal "Requested API access role exceeds the manager's access", result.error
    assert_equal 0, RecordingStudioApi::ApiClient.where(name: "Escalated direct token").count
  end

  test "applies the configured credential ttl when expires_at is omitted" do
    travel_to Time.zone.parse("2026-05-18 12:00:00 UTC") do
      RecordingStudioApi.configuration.credential_ttl = 2.hours

      result = RecordingStudioApi::Services::ProvisionApiClient.call(
        access_recording: @access_recording,
        name: "TTL token"
      )

      assert result.success?, result.error
      assert_equal 2.hours.from_now, result.value.fetch(:credential).expires_at
    end
  end

  test "uses recording topology over legacy access_recording column" do
    result = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: @access_recording,
      name: "Compatibility token"
    )

    assert result.success?, result.error

    _other_root, other_access_recording = create_access_recording_for(
      user: @user,
      workspace_name: "Other workspace"
    )

    credential = result.value.fetch(:credential)
    credential.update_column(:access_recording_id, other_access_recording.id)

    assert_equal result.value.fetch(:access_recording).id, credential.reload.effective_access_recording_id
  end
end
