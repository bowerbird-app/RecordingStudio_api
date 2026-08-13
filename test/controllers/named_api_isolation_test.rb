# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"

class NamedApiIsolationTest < ActionDispatch::IntegrationTest
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    RecordingStudioApi.configuration.api(:operations) { |api| api.default_access = :read_only }
    RecordingStudioApi.configuration.recordable_registry.instance_variable_get(:@registrations).delete("Workspace")
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      serializer: ->(_workspace, **) { { audience: "public" } },
      output_keys: %i[audience],
      relationships: {
        public_folders: { source: :children, child_type: "Folder", many: true,
                          serializer: ->(recordable, **) { { name: recordable.name } }, output_keys: %i[name], limit: 20,
                          endpoints: %i[index] }
      }
    )
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      api: :operations,
      serializer: ->(_workspace, **) { { audience: "operations" } },
      output_keys: %i[audience],
      relationships: {
        folders: { source: :children, child_type: "Folder", many: true,
                   serializer: ->(recordable, **) { { name: recordable.name } }, output_keys: %i[name], limit: 20,
                   endpoints: %i[index show] }
      }
    )
    RecordingStudioApi.register_default_resource_actions!
    RecordingStudioApi.register_recordable_type_api(
      "Folder",
      api: :operations,
      serializer: ->(recordable, **) { { name: recordable.name } },
      output_keys: %i[name],
      operations: %i[index show]
    )

    user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: user)
    @public_token = issue_oauth_access_token_for(access_recording: @access_recording)
    @operations_token = issue_operations_token
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "named api rejects public tokens and exposes only its registered resources" do
    get operations_root_path, headers: bearer_headers(@public_token)
    assert_response :unauthorized

    get operations_root_path, headers: bearer_headers(@operations_token)
    assert_response :success
    assert_equal %w[folders workspaces], JSON.parse(response.body).fetch("resources").map { |resource| resource.fetch("name") }.sort
  end

  test "named api uses its own serializer and read only operation defaults" do
    get "#{operations_root_path}/workspaces", headers: bearer_headers(@operations_token)

    assert_response :success
    records = JSON.parse(response.body).fetch("records")
    assert_not_empty records
    assert_equal "operations", records.first.fetch("audience")

    post "#{operations_root_path}/workspaces",
         params: { attributes: { name: "Blocked write" } },
         headers: bearer_headers(@operations_token)

    assert_response :unprocessable_content
    assert_equal 0, Workspace.where(name: "Blocked write").count
  end

  test "named api shows a direct configured child relationship record" do
    folder_recording = RecordingStudio::Recording.create!(
      recordable: Folder.create!(name: "Operations child"),
      parent_recording: @root_recording
    )

    get "#{operations_root_path}/workspaces/#{@root_recording.id}/folders/#{folder_recording.id}",
        headers: bearer_headers(@operations_token)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal folder_recording.id, payload.fetch("id")
    assert_equal "Folder", payload.fetch("type")
    refute payload.key?("data")
  end

  test "named api nested routes use only the named relationship registry" do
    folder_recording = RecordingStudio::Recording.create!(
      recordable: Folder.create!(name: "Operations child"),
      parent_recording: @root_recording
    )

    get "#{operations_root_path}/workspaces/#{@root_recording.id}/folders", headers: bearer_headers(@operations_token)
    assert_response :success
    assert_equal [folder_recording.id], JSON.parse(response.body).fetch("records").map { |record| record.fetch("id") }

    get "#{operations_root_path}/workspaces/#{@root_recording.id}/public_folders", headers: bearer_headers(@operations_token)
    assert_response :unprocessable_entity

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/public_folders", headers: bearer_headers(@public_token)
    assert_response :success
    assert_equal [folder_recording.id], JSON.parse(response.body).fetch("records").map { |record| record.fetch("id") }

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders", headers: bearer_headers(@public_token)
    assert_response :unprocessable_entity
  end

  private

  def issue_operations_token
    provision_result = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_point_recording: access_point_recording_for(@access_recording),
      manager_actor: access_manager_for(@access_recording),
      role: @access_recording.recordable.role,
      name: "Operations client",
      api: :operations
    )
    raise provision_result.error unless provision_result.success?

    payload = provision_result.value
    token_result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: payload.fetch(:credential).oauth_client_id,
      client_secret: payload.fetch(:token),
      api: :operations
    )
    raise token_result.error unless token_result.success?

    token_result.value.fetch(:access_token)
  end

  def operations_root_path
    "/recording_studio_api/apis/operations/v1"
  end

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end