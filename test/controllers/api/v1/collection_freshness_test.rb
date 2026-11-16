# frozen_string_literal: true

require_relative "../../../support/api_dummy_helpers"

class ApiV1CollectionFreshnessTest < ActionDispatch::IntegrationTest
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user, role: :edit)
    @page_recording = create_page_recording(root_recording: @root_recording, page_title: "Freshness page")
    @access_token = issue_oauth_access_token_for(access_recording: @access_recording, name: "Freshness token")
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "a matching conditional request returns 304 without the page query or recordable load" do
    first_sql = capture_sql do
      get pages_path, params: { limit: 50 }, headers: authorization_headers
    end

    assert_response :success
    assert_includes response.headers["Cache-Control"], "private"
    assert_includes response.headers["Cache-Control"], "must-revalidate"
    etag = response.headers["ETag"]
    last_modified = response.headers["Last-Modified"]
    assert etag.present?
    assert last_modified.present?
    payload = JSON.parse(response.body)
    refute payload.fetch("meta").key?("total_count")
    assert(first_sql.any? { |sql| collection_page_query?(sql) })

    revisit_sql = capture_sql do
      get pages_path, params: { limit: 50 }, headers: authorization_headers.merge("If-None-Match" => etag)
    end

    assert_response :not_modified
    assert_equal "", response.body
    assert(revisit_sql.any? { |sql| aggregate_query?(sql) })
    assert_empty(revisit_sql.select { |sql| collection_page_query?(sql) })
    refute(revisit_sql.any? { |sql| sql.match?(/FROM "?pages"?/i) })

    modified_since_sql = capture_sql do
      get pages_path, params: { limit: 50 }, headers: authorization_headers.merge("If-Modified-Since" => last_modified)
    end

    assert_response :not_modified
    assert_equal "", response.body
    refute(modified_since_sql.any? { |sql| collection_page_query?(sql) })
  end

  test "include_total adds the count and does not reuse an etag from a request without it" do
    get pages_path, params: { limit: 50 }, headers: authorization_headers
    etag = response.headers["ETag"]

    get pages_path, params: { limit: 50, include_total: "true" }, headers: authorization_headers.merge("If-None-Match" => etag)

    assert_response :success
    assert_equal 1, JSON.parse(response.body).fetch("meta").fetch("total_count")
  end

  test "a different page cursor and a changed recording miss the previous etag" do
    get pages_path, params: { limit: 50 }, headers: authorization_headers
    etag = response.headers["ETag"]

    get pages_path, params: { limit: 1 }, headers: authorization_headers.merge("If-None-Match" => etag)
    assert_response :success

    @page_recording.update_columns(updated_at: 1.hour.from_now)
    get pages_path, params: { limit: 50 }, headers: authorization_headers.merge("If-None-Match" => etag)
    assert_response :success
    assert_not_equal etag, response.headers["ETag"]
  end

  test "a different filter misses the previous etag" do
    create_page_recording(root_recording: @root_recording, folder_name: "Marketing", page_title: "Other")
    get folders_path, headers: authorization_headers
    etag = response.headers["ETag"]

    get folders_path, params: { filter: { name: "Marketing" } }, headers: authorization_headers.merge("If-None-Match" => etag)

    assert_response :success
    names = JSON.parse(response.body).fetch("records").map { |record| record.fetch("name") }
    assert_equal ["Marketing"], names
  end

  test "another grant does not receive 304 for this grant's etag" do
    get pages_path, params: { limit: 50 }, headers: authorization_headers
    etag = response.headers["ETag"]

    other_user = create_user
    _other_root, other_access = create_access_recording_for(user: other_user, role: :edit)
    other_page = create_page_recording(root_recording: other_access.root_recording, page_title: "Other grant page")
    other_token = issue_oauth_access_token_for(access_recording: other_access, name: "Other grant token")

    get pages_path, params: { limit: 50 }, headers: { "Authorization" => "Bearer #{other_token}", "If-None-Match" => etag }

    assert_response :success
    ids = JSON.parse(response.body).fetch("records").map { |record| record.fetch("id") }
    assert_includes ids, other_page.id.to_s
    refute_includes ids, @page_recording.id.to_s
  end

  test "a missing credential is unauthorized even with a conditional header" do
    get pages_path, params: { limit: 50 }, headers: authorization_headers
    etag = response.headers["ETag"]

    get pages_path, params: { limit: 50 }, headers: { "If-None-Match" => etag }

    assert_response :unauthorized
  end

  test "an invalid pagination token is rejected before a conditional response" do
    get pages_path, params: { limit: 50 }, headers: authorization_headers
    etag = response.headers["ETag"]

    get pages_path,
        params: { limit: 50, pagination_token: "not-a-token" },
        headers: authorization_headers.merge("If-None-Match" => etag)

    assert_response :unprocessable_entity
    assert_equal "Invalid pagination token", JSON.parse(response.body).dig("error", "message")
  end

  test "include_total must be true or false" do
    get pages_path, params: { include_total: "sometimes" }, headers: authorization_headers

    assert_response :unprocessable_entity
    assert_equal "include_total must be true or false", JSON.parse(response.body).dig("error", "message")
  end

  test "a custom index handler does not send a collection validator" do
    RecordingStudioApi.register_resource_handler("Page", :index, handler: lambda { |_context|
      { json: { handled: "index" } }
    })

    get pages_path, headers: authorization_headers.merge("If-None-Match" => 'W/"stale"')

    assert_response :success
    assert_equal({ "handled" => "index" }, JSON.parse(response.body))
  end

  test "a parent outside the grant is not modified into a 304" do
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      relationships: {
        folders: {
          source: :children,
          child_type: "Folder",
          many: true,
          serializer: ->(recordable, **) { { name: recordable.name } },
          output_keys: %i[name],
          limit: 20,
          endpoints: %i[index]
        }
      }
    )
    get nested_folders_path(@root_recording), headers: authorization_headers
    etag = response.headers["ETag"]

    outsider = create_user
    _outsider_root, outsider_access = create_access_recording_for(user: outsider, role: :edit)
    outsider_token = issue_oauth_access_token_for(access_recording: outsider_access, name: "Outsider token")

    get nested_folders_path(@root_recording),
        headers: { "Authorization" => "Bearer #{outsider_token}", "If-None-Match" => etag }

    assert_response :not_found
    assert_equal "Parent resource was not found in this API scope", JSON.parse(response.body).dig("error", "message")
  end

  test "workspace includes load from the page and a 304 skips that query" do
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      relationships: {
        folders: {
          source: :children,
          child_type: "Folder",
          many: true,
          include: true,
          limit: 20,
          serializer: ->(folder, **) { { name: folder.name } },
          output_keys: %i[name]
        }
      }
    )

    first_sql = capture_sql do
      get workspaces_path, headers: authorization_headers
    end

    assert_response :success
    assert(first_sql.any? { |sql| sql.include?("LATERAL") })
    etag = response.headers["ETag"]

    revisit_sql = capture_sql do
      get workspaces_path, headers: authorization_headers.merge("If-None-Match" => etag)
    end

    assert_response :not_modified
    assert_equal "", response.body
    assert(revisit_sql.any? { |sql| aggregate_query?(sql) })
    refute(revisit_sql.any? { |sql| sql.include?("LATERAL") })
    refute(revisit_sql.any? { |sql| sql.match?(/FROM "?folders"?/i) })
  end

  private

  def pages_path
    "/recording_studio_api/api/v1/pages"
  end

  def folders_path
    "/recording_studio_api/api/v1/folders"
  end

  def workspaces_path
    "/recording_studio_api/api/v1/workspaces"
  end

  def nested_folders_path(workspace)
    "/recording_studio_api/api/v1/workspaces/#{workspace.id}/folders"
  end

  def authorization_headers
    { "Authorization" => "Bearer #{@access_token}" }
  end

  def capture_sql(&)
    queries = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s.squish
      next if payload[:name] == "SCHEMA" || sql.match?(/\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)

      queries << sql
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record", &)
    queries
  end

  def aggregate_query?(sql)
    sql.include?("MAX(") && sql.match?(/COUNT\(/)
  end

  def collection_page_query?(sql)
    sql.include?("recording_studio_recordings") && sql.match?(/ORDER BY/) && sql.match?(/\bLIMIT\b/) && !sql.include?("MAX(") && !sql.include?("LATERAL")
  end
end
