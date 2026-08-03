# frozen_string_literal: true

require_relative "support/api_dummy_helpers"

class ApiClientManagementPolicyTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    configure_dummy_operations_api!
    RecordingStudio.enable_capability(:accessible, on: "AdminSection")
    RecordingStudio.enable_capability(:api_access_point, on: "AdminSection")
    RecordingStudioApi.register_recordable_type_api("AdminSection", api: :operations)

    @owner = create_user(email: "api-policy-owner@example.com")
    @delegated_manager = create_user(email: "api-policy-delegated@example.com")
    _admin_root, @admin_root_recording = create_admin_root_recording(name: "API policy admin")
    with_access_creation_context do
      access = RecordingStudio::Access.create!(actor: @owner, role: :admin)
      RecordingStudio::Recording.create!(recordable: access, parent_recording: @admin_root_recording)
    end

    @admin_section_recording = RecordingStudio::Recording.create!(
      recordable: AdminSection.create!(key: "api_policy", name: "API policy"),
      parent_recording: @admin_root_recording
    )
    grant_access(@admin_section_recording, actor: @delegated_manager, role: :admin, manager_actor: @owner)

    @admin_api_recording = RecordingStudioApi::Admin::ApiAuthorization.recording_for(
      api: :operations,
      root_recording: @admin_root_recording,
      create: true
    )
    provision = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_point_recording: @admin_section_recording,
      manager_actor: @owner,
      role: :admin,
      name: "Protected operations client",
      api: :operations
    )
    assert provision.success?, provision.error
    @api_client = provision.value.fetch(:api_client)
    @credential = provision.value.fetch(:credential)
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "denies a recording manager without access to the protected API admin recording" do
    policy = RecordingStudioApi::ApiClientManagementPolicy.new(actor: @delegated_manager)

    refute policy.view?(@api_client)
    refute policy.manage?(@api_client)
  end

  test "allows viewing but not management with view access to the API admin recording" do
    grant_access(@admin_root_recording, actor: @delegated_manager, role: :view, manager_actor: @owner)
    policy = RecordingStudioApi::ApiClientManagementPolicy.new(actor: @delegated_manager)

    assert policy.view?(@api_client)
    refute policy.manage?(@api_client)
  end

  test "allows management with edit access to both the client scope and API admin recording" do
    grant_access(
      @admin_root_recording,
      actor: @delegated_manager,
      role: RecordingStudioApi.configuration.access_management_edit_role,
      manager_actor: @owner
    )
    policy = RecordingStudioApi::ApiClientManagementPolicy.new(actor: @delegated_manager)

    assert policy.view?(@api_client)
    assert policy.manage?(@api_client)
  end

  test "direct credential rotation fails without protected API admin access" do
    result = RecordingStudioApi::Services::RotateApiCredential.call(
      api_client: @api_client,
      actor: @delegated_manager
    )

    assert result.failure?
    assert_equal "Actor is not authorized to manage this API client", result.error
    assert_nil @credential.reload.revoked_at
  end

  private

  def grant_access(recording, actor:, role:, manager_actor:)
    result = RecordingStudioAccessible.grant_access(
      recording: recording,
      actor: actor,
      role: role,
      manager_actor: manager_actor
    )
    assert result.success?, result.error
    result.value
  end
end