# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"

class AccessibleScopeRequestsTest < ActionDispatch::IntegrationTest
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @owner = create_user
    @root_recording, = create_access_recording_for(user: @owner, role: :admin)
    @granted_folder = create_folder("Granted", parent: @root_recording)
    @sibling_folder = create_folder("Sibling", parent: @root_recording)
    @child_folder = create_folder("Child", parent: @granted_folder)
    @member = create_user
    access_recording = create_access_recording(parent_recording: @granted_folder, user: @member, role: :edit)
    @token = issue_oauth_access_token_for(access_recording: access_recording, name: "Folder scope token")
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "a folder grant lists its subtree and hides the sibling folder" do
    get "/recording_studio_api/api/v1/folders", headers: authorization_headers

    assert_response :success
    ids = JSON.parse(response.body).fetch("records").map { |row| row.fetch("id") }
    assert_includes ids, @granted_folder.id
    assert_includes ids, @child_folder.id
    assert_not_includes ids, @sibling_folder.id
  end

  test "show and update outside the folder grant return not found" do
    get "/recording_studio_api/api/v1/folders/#{@sibling_folder.id}", headers: authorization_headers
    assert_response :not_found
    assert_equal api_scope_missing_message("Folder"), JSON.parse(response.body).dig("error", "message")

    patch "/recording_studio_api/api/v1/folders/#{@sibling_folder.id}",
          params: { name: "Renamed sibling" },
          headers: authorization_headers
    assert_response :not_found
    assert_equal api_scope_missing_message("Folder"), JSON.parse(response.body).dig("error", "message")
    assert_equal "Sibling", @sibling_folder.recordable.reload.name
  end

  test "create with a parent outside the folder grant returns not found" do
    post "/recording_studio_api/api/v1/folders",
         params: { parent_id: @sibling_folder.id, name: "Blocked child" },
         headers: authorization_headers

    assert_response :not_found
    assert_equal "Parent resource was not found in this API scope", JSON.parse(response.body).dig("error", "message")
    assert_nil Folder.find_by(name: "Blocked child")

    post "/recording_studio_api/api/v1/folders",
         params: { parent_id: @root_recording.id, name: "Blocked root child" },
         headers: authorization_headers

    assert_response :not_found
    assert_equal "Parent resource was not found in this API scope", JSON.parse(response.body).dig("error", "message")
  end

  test "a second root stays hidden from the folder grant" do
    other_root, = create_access_recording_for(user: create_user, role: :admin, workspace_name: "Second root")
    other_folder = create_folder("Elsewhere", parent: other_root)

    get "/recording_studio_api/api/v1/folders/#{other_folder.id}", headers: authorization_headers
    assert_response :not_found

    patch "/recording_studio_api/api/v1/folders/#{other_folder.id}",
          params: { name: "Taken" },
          headers: authorization_headers
    assert_response :not_found
    assert_equal "Elsewhere", other_folder.recordable.reload.name
  end

  test "a trashed descendant is hidden and a kept child of a trashed folder stays visible" do
    @child_folder.update_column(:trashed_at, Time.current)
    kept_under_trash = create_folder("Still here", parent: @child_folder)

    get "/recording_studio_api/api/v1/folders", headers: authorization_headers
    assert_response :success
    ids = JSON.parse(response.body).fetch("records").map { |row| row.fetch("id") }
    assert_not_includes ids, @child_folder.id
    assert_includes ids, kept_under_trash.id

    get "/recording_studio_api/api/v1/folders/#{@child_folder.id}", headers: authorization_headers
    assert_response :not_found

    get "/recording_studio_api/api/v1/folders/#{kept_under_trash.id}", headers: authorization_headers
    assert_response :success

    patch "/recording_studio_api/api/v1/folders/#{kept_under_trash.id}",
          params: { name: "Renamed under trash" },
          headers: authorization_headers
    assert_response :success
    assert_equal "Renamed under trash", kept_under_trash.reload.recordable.name
  end

  private

  def create_folder(name, parent:)
    RecordingStudio::Recording.create!(
      recordable: Folder.create!(name: name),
      parent_recording: parent
    )
  end

  def authorization_headers
    { "Authorization" => "Bearer #{@token}" }
  end
end
