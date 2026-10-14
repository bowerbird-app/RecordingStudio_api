# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"

class ListTotalCountTest < ActionDispatch::IntegrationTest
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user, role: :edit)
    @access_token = issue_oauth_access_token_for(access_recording: @access_recording, name: "List count token")
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
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "folder list meta includes total_count for the whole filtered set" do
    create_folder("Marketing")
    create_folder("Archive")

    get "/recording_studio_api/api/v1/folders", headers: authorization_headers

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal %w[limit sort order has_more next_pagination_token total_count filter], payload.fetch("meta").keys
    assert_equal(
      {
        "limit" => 50,
        "sort" => "created_at",
        "order" => "asc",
        "has_more" => false,
        "next_pagination_token" => nil,
        "total_count" => 2,
        "filter" => {}
      },
      payload.fetch("meta")
    )
    assert_equal 2, payload.fetch("records").length
  end

  test "filtered and searched lists count matching recordings and keep meta key order" do
    create_folder("Marketing")
    create_folder("Archive")

    get "/recording_studio_api/api/v1/folders",
        params: { filter: { name: "Marketing" } },
        headers: authorization_headers

    assert_response :success
    filtered = JSON.parse(response.body)
    assert_equal(["Marketing"], filtered.fetch("records").map { |row| row.fetch("name") })
    assert_equal 1, filtered.fetch("meta").fetch("total_count")
    assert_equal({ "name" => "Marketing" }, filtered.fetch("meta").fetch("filter"))

    get "/recording_studio_api/api/v1/folders",
        params: { q: "Archive" },
        headers: authorization_headers

    assert_response :success
    searched = JSON.parse(response.body)
    assert_equal(["Archive"], searched.fetch("records").map { |row| row.fetch("name") })
    assert_equal 1, searched.fetch("meta").fetch("total_count")
    assert_equal "Archive", searched.fetch("meta").fetch("q")

    get "/recording_studio_api/api/v1/folders",
        params: { filter: { name: "Marketing" }, q: "Market" },
        headers: authorization_headers

    assert_response :success
    both = JSON.parse(response.body)
    assert_equal %w[limit sort order has_more next_pagination_token total_count filter q], both.fetch("meta").keys
    assert_equal 1, both.fetch("meta").fetch("total_count")
    assert_equal(["Marketing"], both.fetch("records").map { |row| row.fetch("name") })
  end

  test "total_count stays the same on every page" do
    first = create_folder("First")
    second = create_folder("Second")

    get "/recording_studio_api/api/v1/folders", params: { limit: 1 }, headers: authorization_headers

    assert_response :success
    first_page = JSON.parse(response.body)
    assert_equal 1, first_page.fetch("records").length
    assert_equal true, first_page.fetch("meta").fetch("has_more")
    assert_equal 2, first_page.fetch("meta").fetch("total_count")

    get "/recording_studio_api/api/v1/folders",
        params: { limit: 1, pagination_token: first_page.fetch("meta").fetch("next_pagination_token") },
        headers: authorization_headers

    assert_response :success
    second_page = JSON.parse(response.body)
    assert_equal 1, second_page.fetch("records").length
    assert_equal false, second_page.fetch("meta").fetch("has_more")
    assert_nil second_page.fetch("meta").fetch("next_pagination_token")
    assert_equal 2, second_page.fetch("meta").fetch("total_count")
    assert_equal [first.id, second.id].sort, (first_page.fetch("records") + second_page.fetch("records")).map { |row| row.fetch("id") }.sort
  end

  test "count=true returns only total_count and does not serialize rows" do
    create_folder("Marketing")
    create_folder("Archive")

    RecordingStudioApi::Serializers::ResourceRecordingSerializer.stub(:call, proc { raise "serialized a row" }) do
      get "/recording_studio_api/api/v1/folders",
          params: { filter: { name: "Marketing" }, count: "true", limit: 1, sort: "not-a-field", pagination_token: "not-a-token" },
          headers: authorization_headers
    end

    assert_response :success
    assert_equal '{"total_count":1}', response.body
  end

  test "count accepts true, 1, false, 0, blank, and rejects anything else" do
    create_folder("Marketing")
    create_folder("Archive")

    get "/recording_studio_api/api/v1/folders", params: { count: "1" }, headers: authorization_headers
    assert_response :success
    assert_equal '{"total_count":2}', response.body

    get "/recording_studio_api/api/v1/folders", params: { count: " TRUE " }, headers: authorization_headers
    assert_response :success
    assert_equal '{"total_count":2}', response.body

    get "/recording_studio_api/api/v1/folders", params: { count: "false" }, headers: authorization_headers
    assert_response :success
    listed = JSON.parse(response.body)
    assert_equal 2, listed.fetch("records").length
    assert_equal 2, listed.fetch("meta").fetch("total_count")
    assert_equal %w[resource type records meta], listed.keys

    get "/recording_studio_api/api/v1/folders", params: { count: "0" }, headers: authorization_headers
    assert_response :success
    assert_equal 2, JSON.parse(response.body).fetch("records").length

    get "/recording_studio_api/api/v1/folders", params: { count: "" }, headers: authorization_headers
    assert_response :success
    assert_equal 2, JSON.parse(response.body).fetch("records").length

    get "/recording_studio_api/api/v1/folders", params: { count: "maybe" }, headers: authorization_headers
    assert_response :unprocessable_entity
    assert_equal(
      { "error" => { "code" => "invalid_input", "message" => "count must be true or false" } },
      JSON.parse(response.body)
    )
  end

  test "a caller without access gets the same status with and without count=true" do
    get "/recording_studio_api/api/v1/folders"
    assert_response :unauthorized
    without_count = response.status
    without_body = response.body

    get "/recording_studio_api/api/v1/folders", params: { count: "true" }
    assert_equal without_count, response.status
    assert_equal without_body, response.body
    assert_equal "authentication_failed", JSON.parse(response.body).dig("error", "code")
  end

  test "nested list meta counts children before per-child authorize hooks" do
    create_folder("Marketing")
    create_folder("Archive")
    create_folder("Notes")

    get nested_folders_path, headers: authorization_headers

    assert_response :success
    listed = JSON.parse(response.body)
    assert_equal %w[limit sort order has_more next_pagination_token total_count], listed.fetch("meta").keys
    refute listed.fetch("meta").key?("filter")
    refute listed.fetch("meta").key?("q")
    assert_equal 3, listed.fetch("meta").fetch("total_count")
    assert_equal 3, listed.fetch("records").length

    with_rejecting_child_authorize do |calls|
      get nested_folders_path, params: { count: "true" }, headers: authorization_headers
      assert_response :success
      assert_equal '{"total_count":3}', response.body
      assert_empty calls

      get nested_folders_path, headers: authorization_headers
      assert_response :success
      hidden = JSON.parse(response.body)
      assert_equal [], hidden.fetch("records")
      assert_equal 3, hidden.fetch("meta").fetch("total_count")
      refute_empty calls
    end
  end

  test "nested count=true still requires the parent to be in scope" do
    create_folder("Marketing")
    outsider = create_user
    _root, access_recording = create_access_recording_for(user: outsider, role: :edit)
    outsider_token = issue_oauth_access_token_for(access_recording: access_recording, name: "Outsider")
    headers = { "Authorization" => "Bearer #{outsider_token}" }

    get nested_folders_path, headers: headers
    assert_response :not_found
    assert_equal "Parent resource was not found in this API scope", JSON.parse(response.body).dig("error", "message")

    get nested_folders_path, params: { count: "true" }, headers: headers
    assert_response :not_found
    assert_equal(
      { "error" => { "code" => "not_found", "message" => "Parent resource was not found in this API scope" } },
      JSON.parse(response.body)
    )
  end

  test "a custom index handler does not gain total_count or count=true" do
    create_folder("Marketing")
    RecordingStudioApi.register_resource_handler("Folder", :index, handler: lambda { |_context|
      { json: { handled: "index" } }
    })

    get "/recording_studio_api/api/v1/folders", params: { count: "true" }, headers: authorization_headers

    assert_response :success
    assert_equal({ "handled" => "index" }, JSON.parse(response.body))
  end

  test "a multiplying join counts distinct recordings" do
    recording = create_folder("Marketing")
    relation = RecordingStudio::Recording.where(id: recording.id).joins(
      "CROSS JOIN (VALUES (1), (2)) AS list_count_duplicates(n)"
    )
    assert_equal 2, relation.count

    pagination = RecordingStudioApi::Services::PaginateResourceCollection.call(
      relation: relation,
      resource: "folders",
      recordable_type: "Folder",
      limit: 50,
      pagination_token: nil,
      sort: nil,
      order: nil,
      api: :public,
      scope_key: "client:distinct"
    )

    assert pagination.success?
    page = pagination.value
    body = page.response_body { |rows, meta| { ids: rows.map(&:id), meta: meta } }
    assert_equal [recording.id], body.fetch(:ids).uniq
    assert_equal 1, body.fetch(:meta).fetch(:total_count)

    counted = RecordingStudioApi::Services::PaginateResourceCollection.call(
      relation: relation,
      resource: "folders",
      recordable_type: "Folder",
      limit: 1,
      pagination_token: "ignored",
      sort: "not-a-field",
      order: "sideways",
      count: "true",
      api: :public,
      scope_key: "client:distinct"
    )

    assert counted.success?
    assert_equal({ total_count: 1 }, counted.value.response_body { raise "yielded rows" })
  end

  private

  def authorization_headers
    { "Authorization" => "Bearer #{@access_token}" }
  end

  def create_folder(name)
    RecordingStudio::Recording.create!(
      recordable: Folder.create!(name: name),
      parent_recording: @root_recording
    )
  end

  def nested_folders_path
    "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}/folders"
  end

  def with_rejecting_child_authorize
    klass = RecordingStudioApi::RelationshipContext
    original = klass.instance_method(:authorized_targets)
    calls = []
    klass.define_method(:authorized_targets) do |targets, *_rest|
      calls << targets.map(&:id)
      raise RecordingStudioApi::AuthorizationError, "hidden child"
    end
    yield calls
  ensure
    klass.define_method(:authorized_targets, original)
  end
end
