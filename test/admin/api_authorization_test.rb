# frozen_string_literal: true

require "rake"
require_relative "../support/api_dummy_helpers"

class ApiAuthorizationTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @actor = create_user(email: "admin-api-auth@example.com")
    _admin_root, @root_recording = create_admin_root_recording(name: "Auth check admin")
    create_access_recording(parent_recording: @root_recording, user: @actor, role: :admin)
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "an authorization check creates no records when the admin api recording is missing" do
    assert_no_writes do
      assert_nil RecordingStudioApi::Admin::ApiAuthorization.recording_for(api: :public, root_recording: @root_recording)
      refute RecordingStudioApi::Admin::ApiAuthorization.authorized?(
        actor: @actor,
        api: :public,
        root_recording: @root_recording,
        role: RecordingStudioApi.configuration.access_management_view_role
      )
    end
  end

  test "an authorization check creates no records after the admin api recording exists" do
    recording = RecordingStudioApi::Admin::ApiAuthorization.provision!(
      api: :public,
      root_recording: @root_recording,
      actor: @actor
    )

    assert_no_writes do
      assert_equal recording, RecordingStudioApi::Admin::ApiAuthorization.recording_for(api: :public, root_recording: @root_recording)
      assert RecordingStudioApi::Admin::ApiAuthorization.authorized?(
        actor: @actor,
        api: :public,
        root_recording: @root_recording,
        role: RecordingStudioApi.configuration.access_management_view_role
      )
    end
  end

  test "a management policy check creates no records" do
    configure_dummy_operations_api!
    client = RecordingStudioApi::ApiClient.create!(name: "Policy check", api_key: "operations", owner: @actor)
    access_recording = with_access_creation_context do
      access = RecordingStudio::Access.create!(actor: client, role: :admin)
      RecordingStudio::Recording.create!(recordable: access, parent_recording: @root_recording)
    end
    client.update_columns(access_recording_id: access_recording.id, updated_at: Time.current)

    assert_no_writes do
      policy = RecordingStudioApi::ApiClientManagementPolicy.new(actor: @actor)
      refute policy.view?(client)
      refute policy.manage?(client)
    end
  end

  test "provision_admin records every admin root and can run again" do
    Current.actor = @actor
    Rails.application.load_tasks unless Rake::Task.task_defined?("recording_studio_api:provision_admin")
    task = Rake::Task["recording_studio_api:provision_admin"]
    task.reenable
    task.invoke

    recording = RecordingStudioApi::Admin::ApiAuthorization.recording_for(api: :public, root_recording: @root_recording)
    assert_equal @root_recording.id, recording.parent_recording_id

    assert_no_writes do
      task.reenable
      task.invoke
    end
  end

  test "provisioning records the admin api once under the admin root" do
    first = RecordingStudioApi::Admin::ApiAuthorization.provision!(
      api: :public,
      root_recording: @root_recording,
      actor: @actor
    )
    key = "recording-studio-api/admin-api/public/#{@root_recording.id}"

    assert_equal @root_recording.id, first.parent_recording_id
    assert_equal @root_recording.id, first.root_recording_id
    assert_equal "RecordingStudioApi::AdminApi", first.recordable_type
    assert_equal "api", first.recordable.key
    assert_equal key, first.events(actions: "created").first.idempotency_key

    assert_no_writes do
      second = RecordingStudioApi::Admin::ApiAuthorization.provision!(
        api: :public,
        root_recording: @root_recording,
        actor: @actor
      )
      assert_equal first.id, second.id
    end
  end

  private

  def assert_no_writes(&)
    assert_no_difference -> { RecordingStudioApi::AdminApi.count } do
      assert_no_difference -> { RecordingStudio::Recording.count } do
        assert_no_difference -> { RecordingStudio::Event.count }, &
      end
    end
  end
end
