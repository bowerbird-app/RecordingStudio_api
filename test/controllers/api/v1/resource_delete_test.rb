# frozen_string_literal: true

require_relative "../../../support/api_dummy_helpers"

class ApiV1ResourceDeleteTest < ActionDispatch::IntegrationTest
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user, role: :edit)
    @access_token = issue_oauth_access_token_for(access_recording: @access_recording, name: "Edit token")
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "delete trashes a trashable recording and keeps its history" do
    folder_recording = RecordingStudio::Recording.create!(
      recordable: Folder.create!(name: "Trash me"),
      parent_recording: @root_recording
    )
    page_recording = RecordingStudio::Recording.create!(
      recordable: Page.create!(title: "Nested page"),
      parent_recording: folder_recording
    )
    folder_recording.log_event!(action: "noted", actor: @user, metadata: { source: "test" })
    noted_id = folder_recording.events.pick(:id)

    delete "/recording_studio_api/api/v1/folders/#{folder_recording.id}", headers: authorization_headers

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal folder_recording.id, payload.fetch("id")
    assert_equal true, payload.fetch("deleted")
    assert_equal "trashed", payload.fetch("deleted_via")

    folder_recording.reload
    page_recording.reload
    assert folder_recording.trashed_at.present?
    assert page_recording.trashed_at.present?
    assert folder_recording.trash_root
    refute page_recording.trash_root
    assert RecordingStudio::Event.exists?(noted_id)
    assert folder_recording.events.exists?(action: "trashed")
    assert page_recording.events.exists?(action: "trashed")
    assert Folder.exists?(folder_recording.recordable_id)

    get "/recording_studio_api/api/v1/folders", headers: authorization_headers
    assert_response :success
    listed_ids = JSON.parse(response.body).fetch("records").map { |record| record.fetch("id") }
    refute_includes listed_ids, folder_recording.id

    get "/recording_studio_api/api/v1/folders/#{folder_recording.id}", headers: authorization_headers
    assert_response :not_found

    get "/recording_studio_api/api/v1/pages/#{page_recording.id}", headers: authorization_headers
    assert_response :not_found
  end

  test "a view key cannot trash a trashable recording" do
    _view_root, view_access = create_access_recording_for(user: create_user(email: "view-trash@example.com"), role: :view)
    folder_recording = RecordingStudio::Recording.create!(
      recordable: Folder.create!(name: "View blocked"),
      parent_recording: view_access.root_recording
    )
    view_token = issue_oauth_access_token_for(access_recording: view_access, name: "View token")

    delete "/recording_studio_api/api/v1/folders/#{folder_recording.id}",
           headers: { "Authorization" => "Bearer #{view_token}" }

    assert_response :forbidden
    assert_nil folder_recording.reload.trashed_at
    refute folder_recording.events.exists?(action: "trashed")
  end

  private

  def authorization_headers
    { "Authorization" => "Bearer #{@access_token}" }
  end
end
