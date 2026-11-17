# frozen_string_literal: true

require_relative "../../../support/api_dummy_helpers"

class ApiV1TokenOwnerAccessTest < ActionDispatch::IntegrationTest
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "a revoked owner hides the token's records" do
    owner = create_user
    root, owner_access = create_access_recording_for(user: owner, role: :admin)
    page = create_page_recording(root_recording: root)
    other = create_user
    grant_or_bootstrap_access!(recording: root, actor: other, role: :admin)
    token, client = issue_owner_token(access_point: root, manager: owner, role: :admin, name: "Owner key")

    assert_equal owner, client.owner
    get "/recording_studio_api/api/v1/pages/#{page.id}", headers: bearer(token)
    assert_response :success

    revoked = RecordingStudioAccessible::Services::RevokeRecordingAccess.call(
      recording: root,
      access_recording: owner_access,
      manager_actor: other,
      allow_last_admin_removal: true
    )
    assert revoked.success?

    get "/recording_studio_api/api/v1/pages", headers: bearer(token)
    assert_response :forbidden

    get "/recording_studio_api/api/v1/pages/#{page.id}", headers: bearer(token)
    assert_response :not_found

    grant = grant_for(client)
    assert_not_includes grant.accessible_recordings.pluck(:id), page.id
  end

  test "a token anchored on a folder sees only that subtree" do
    owner = create_user
    root, = create_access_recording_for(user: owner, role: :admin)
    granted = folder("Granted", root)
    child = folder("Child", granted)
    sibling = folder("Sibling", root)
    token, = issue_owner_token(access_point: granted, manager: owner, role: :edit, name: "Folder key")

    get "/recording_studio_api/api/v1/folders", headers: bearer(token)
    assert_response :success
    ids = JSON.parse(response.body).fetch("records").map { |row| row.fetch("id") }

    assert_includes ids, granted.id
    assert_includes ids, child.id
    assert_not_includes ids, sibling.id
    assert_not_includes ids, root.id

    get "/recording_studio_api/api/v1/folders/#{sibling.id}", headers: bearer(token)
    assert_response :not_found
  end

  test "a narrower grant role is enforced when the owner is an admin" do
    owner = create_user
    root, = create_access_recording_for(user: owner, role: :admin)
    page = create_page_recording(root_recording: root)
    token, = issue_owner_token(access_point: root, manager: owner, role: :view, name: "View key")

    get "/recording_studio_api/api/v1/pages/#{page.id}", headers: bearer(token)
    assert_response :success

    patch "/recording_studio_api/api/v1/pages/#{page.id}",
          params: { title: "Blocked" },
          headers: bearer(token)
    assert_response :forbidden
    assert_equal "API access grant is not authorized for this capability", JSON.parse(response.body).dig("error", "message")
    refute_equal "Blocked", page.recordable.reload.title
  end

  test "a narrower owner role is enforced when the grant is admin" do
    owner = create_user
    root, = create_access_recording_for(user: owner, role: :admin)
    page = create_page_recording(root_recording: root)
    other = create_user
    grant_or_bootstrap_access!(recording: root, actor: other, role: :admin)
    token, = issue_owner_token(access_point: root, manager: owner, role: :admin, name: "Admin key")

    downgraded = RecordingStudioAccessible.grant_access(
      recording: root,
      actor: owner,
      role: :view,
      manager_actor: other
    )
    assert downgraded.success?

    get "/recording_studio_api/api/v1/pages/#{page.id}", headers: bearer(token)
    assert_response :success

    patch "/recording_studio_api/api/v1/pages/#{page.id}",
          params: { title: "Blocked by owner" },
          headers: bearer(token)
    assert_response :forbidden
    refute_equal "Blocked by owner", page.recordable.reload.title
  end

  test "a root grant lists without a recursive walk" do
    owner = create_user
    root, = create_access_recording_for(user: owner, role: :admin)
    page = create_page_recording(root_recording: root)
    token, = issue_owner_token(access_point: root, manager: owner, role: :admin, name: "Root key")
    queries = capture_sql do
      get "/recording_studio_api/api/v1/pages?limit=50", headers: bearer(token)
    end

    assert_response :success
    ids = JSON.parse(response.body).fetch("records").map { |row| row.fetch("id") }
    assert_includes ids, page.id

    get "/recording_studio_api/api/v1/workspaces", headers: bearer(token)
    assert_response :success
    workspace_ids = JSON.parse(response.body).fetch("records").map { |row| row.fetch("id") }
    assert_includes workspace_ids, root.id

    sql = queries.join("\n")
    refute_includes sql, "WITH RECURSIVE"
    refute_includes sql, "scope_tree"
    assert_includes sql, "root_recording_id"
  end

  private

  def folder(name, parent)
    RecordingStudio::Recording.create!(
      recordable: Folder.create!(name: name),
      parent_recording: parent
    )
  end

  def issue_owner_token(access_point:, manager:, role:, name:)
    provisioned = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_point_recording: access_point,
      manager_actor: manager,
      role: role,
      name: name
    )
    raise provisioned.error.to_s unless provisioned.success?

    issued = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: provisioned.value.fetch(:credential).oauth_client_id,
      client_secret: provisioned.value.fetch(:token)
    )
    raise issued.error.to_s unless issued.success?

    [issued.value.fetch(:access_token), provisioned.value.fetch(:api_client)]
  end

  def grant_for(client)
    access_recording = client.access_recording
    RecordingStudioApi::AccessGrant.new(
      api_client: client,
      credential: nil,
      access_recording: access_recording,
      root_recording: access_recording.root_recording
    )
  end

  def bearer(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def capture_sql(&)
    queries = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s
      next if payload[:name] == "SCHEMA"
      next if sql.match?(/\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)

      queries << sql.squish
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record", &)
    queries
  end
end
