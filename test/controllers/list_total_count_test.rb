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

  test "folder list meta omits total_count unless include_total is requested" do
    create_folder("Marketing")
    create_folder("Archive")

    get "/recording_studio_api/api/v1/folders", headers: authorization_headers

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal %w[limit sort order has_more next_pagination_token filter], payload.fetch("meta").keys
    refute payload.fetch("meta").key?("total_count")
    assert_equal 2, payload.fetch("records").length

    get "/recording_studio_api/api/v1/folders", params: { include_total: "true" }, headers: authorization_headers

    assert_response :success
    counted = JSON.parse(response.body)
    assert_equal 2, counted.fetch("meta").fetch("total_count")
    assert_equal %w[limit sort order has_more next_pagination_token total_count filter], counted.fetch("meta").keys
  end

  test "folder list meta includes total_count for the whole filtered set when asked" do
    create_folder("Marketing")
    create_folder("Archive")

    get "/recording_studio_api/api/v1/folders", params: { include_total: "true" }, headers: authorization_headers

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
        params: { filter: { name: "Marketing" }, include_total: "true" },
        headers: authorization_headers

    assert_response :success
    filtered = JSON.parse(response.body)
    assert_equal(["Marketing"], filtered.fetch("records").map { |row| row.fetch("name") })
    assert_equal 1, filtered.fetch("meta").fetch("total_count")
    assert_equal({ "name" => "Marketing" }, filtered.fetch("meta").fetch("filter"))

    get "/recording_studio_api/api/v1/folders",
        params: { q: "Archive", include_total: "true" },
        headers: authorization_headers

    assert_response :success
    searched = JSON.parse(response.body)
    assert_equal(["Archive"], searched.fetch("records").map { |row| row.fetch("name") })
    assert_equal 1, searched.fetch("meta").fetch("total_count")
    assert_equal "Archive", searched.fetch("meta").fetch("q")

    get "/recording_studio_api/api/v1/folders",
        params: { filter: { name: "Marketing" }, q: "Market", include_total: "true" },
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

    get "/recording_studio_api/api/v1/folders", params: { limit: 1, include_total: "true" }, headers: authorization_headers

    assert_response :success
    first_page = JSON.parse(response.body)
    assert_equal 1, first_page.fetch("records").length
    assert_equal true, first_page.fetch("meta").fetch("has_more")
    assert_equal 2, first_page.fetch("meta").fetch("total_count")

    get "/recording_studio_api/api/v1/folders",
        params: { limit: 1, include_total: "true", pagination_token: first_page.fetch("meta").fetch("next_pagination_token") },
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
    refute listed.fetch("meta").key?("total_count")
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
    omitted = JSON.parse(response.body)
    assert_equal %w[limit sort order has_more next_pagination_token], omitted.fetch("meta").keys
    refute omitted.fetch("meta").key?("total_count")

    get nested_folders_path, params: { include_total: "true" }, headers: authorization_headers

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

      get nested_folders_path, params: { include_total: "true" }, headers: authorization_headers
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

  test "total_count matches the rows for an unfiltered list, a filter, a search, and a sort join" do
    create_folder("Marketing")
    create_folder("Archive")
    create_folder("Market notes")

    unfiltered = list_folders(include_total: "true")
    assert_equal unfiltered.fetch("records").length, unfiltered.fetch("meta").fetch("total_count")
    assert_equal 3, unfiltered.fetch("meta").fetch("total_count")
    assert_empty count_queries_for({})
    assert_equal 1, count_queries_for({ include_total: "true" }).length
    assert_count_sql('SELECT COUNT(*) FROM "recording_studio_recordings"', params: { include_total: "true" })
    refute_count_sql(/COUNT\(DISTINCT/, params: { include_total: "true" })

    filtered = list_folders(filter: { name: "Marketing" }, include_total: "true")
    filtered_names = filtered.fetch("records").map { |row| row.fetch("name") }
    assert_equal ["Marketing"], filtered_names
    assert_equal filtered.fetch("records").length, filtered.fetch("meta").fetch("total_count")
    assert_count_sql(/COUNT\(DISTINCT/, params: { filter: { name: "Marketing" }, include_total: "true" })

    searched = list_folders(q: "Market", include_total: "true")
    searched_names = searched.fetch("records").map { |row| row.fetch("name") }
    assert_equal ["Market notes", "Marketing"], searched_names.sort
    assert_equal searched.fetch("records").length, searched.fetch("meta").fetch("total_count")
    assert_equal 2, searched.fetch("meta").fetch("total_count")
    assert_count_sql(/COUNT\(DISTINCT/, params: { q: "Market", include_total: "true" })

    sorted = list_folders(sort: "name", order: "asc", include_total: "true")
    sorted_names = sorted.fetch("records").map { |row| row.fetch("name") }
    sort_names = ["Archive", "Market notes", "Marketing"]
    database_order = Folder.where(name: sort_names).order(:name).pluck(:name)
    assert_equal database_order, sorted_names
    assert_equal sort_names.sort, sorted_names.sort
    assert_equal sorted.fetch("records").length, sorted.fetch("meta").fetch("total_count")
    assert_count_sql('SELECT COUNT(*) FROM "recording_studio_recordings"', params: { sort: "name", order: "asc", include_total: "true" })
    assert_page_sql(/INNER JOIN folders recordable_sort_folders/, params: { sort: "name", order: "asc", include_total: "true" })
  end

  test "a distinct list with no join keeps a distinct count" do
    recording = create_folder("Marketing")
    relation = RecordingStudio::Recording.where(id: recording.id).distinct
    count_sql = nil
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      count_sql = payload[:sql].squish if payload[:sql].to_s.match?(/COUNT/i)
    end

    pagination = nil
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      pagination = RecordingStudioApi::Services::PaginateResourceCollection.call(
        relation: relation,
        resource: "folders",
        recordable_type: "Folder",
        limit: 50,
        pagination_token: nil,
        sort: nil,
        order: nil,
        include_total: true,
        api: :public,
        scope_key: "client:already-distinct"
      )
    end

    assert pagination.success?
    body = pagination.value.response_body { |rows, meta| { ids: rows.map(&:id), meta: meta } }
    assert_equal [recording.id], body.fetch(:ids)
    assert_equal 1, body.fetch(:meta).fetch(:total_count)
    assert_match(/COUNT\(DISTINCT/, count_sql)
  end

  test "referenced includes, eager loads, and a custom from keep a distinct count" do
    recording = create_folder("Marketing")
    base = RecordingStudio::Recording.where(id: recording.id)

    referenced = base.includes(:parent_recording).references(:parent_recording)
    assert_match(/COUNT\(DISTINCT/, count_sql_for_relation(referenced, "referenced-include"))

    eager = base.eager_load(:parent_recording)
    assert_match(/COUNT\(DISTINCT/, count_sql_for_relation(eager, "eager-load"))

    custom_from = base.from(RecordingStudio::Recording.table_name)
    assert_match(/COUNT\(DISTINCT/, count_sql_for_relation(custom_from, "custom-from"))

    preloaded = base.includes(:parent_recording)
    assert_match(/SELECT COUNT\(\*\)/, count_sql_for_relation(preloaded, "preload-include"))
  end

  test "a left outer join keeps a distinct count" do
    recording = create_folder("Marketing")
    relation = RecordingStudio::Recording.where(id: recording.id).left_outer_joins(:parent_recording)
    count_sql = nil
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      count_sql = payload[:sql].squish if payload[:sql].to_s.match?(/COUNT/i)
    end

    pagination = nil
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      pagination = RecordingStudioApi::Services::PaginateResourceCollection.call(
        relation: relation,
        resource: "folders",
        recordable_type: "Folder",
        limit: 50,
        pagination_token: nil,
        sort: nil,
        order: nil,
        include_total: true,
        api: :public,
        scope_key: "client:left-join"
      )
    end

    assert pagination.success?
    counted_total = pagination.value.response_body { |_rows, meta| meta.fetch(:total_count) }
    assert_equal 1, counted_total
    assert_match(/COUNT\(DISTINCT/, count_sql)
    assert_match(/LEFT OUTER JOIN/i, count_sql)
  end

  test "the folder list body matches an unpreloaded serializer and loads recordables once" do
    first = create_folder("Marketing")
    second = create_folder("Archive")
    third = create_folder("Notes")
    queries = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s
      next if payload[:name] == "SCHEMA"

      queries << sql.squish
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      get "/recording_studio_api/api/v1/folders", headers: authorization_headers
    end

    assert_response :success
    payload = JSON.parse(response.body)
    expected = [first, second, third].sort_by { |recording| [recording.created_at, recording.id] }.map do |recording|
      fresh = RecordingStudio::Recording.find(recording.id)
      refute fresh.association(:recordable).loaded?
      RecordingStudioApi::Serializers::ResourceRecordingSerializer.call(fresh, version: "v1", api: :public)
    end

    assert_equal expected.map { |record| JSON.parse(record.except("_meta").to_json) }, payload.fetch("records")
    folder_selects = queries.count { |sql| sql.match?(/\ASELECT/i) && sql.match?(/FROM "?folders"?/i) }
    assert_equal 1, folder_selects
    assert_operator folder_selects, :<, payload.fetch("records").length
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
      include_total: true,
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

  def list_folders(params = {})
    get "/recording_studio_api/api/v1/folders", params: params, headers: authorization_headers
    assert_response :success
    JSON.parse(response.body)
  end

  def assert_count_sql(pattern, params:)
    sql = count_sql_for(params)
    assert_match pattern, sql
  end

  def refute_count_sql(pattern, params:)
    sql = count_sql_for(params)
    refute_match pattern, sql
  end

  def assert_page_sql(pattern, params:)
    queries = queries_for(params)
    assert queries.any? { |sql| sql.match?(pattern) }, "expected #{pattern} in #{queries.grep(/JOIN/i)}"
  end

  def count_sql_for(params)
    count_queries_for(params).first
  end

  def count_queries_for(params)
    queries_for(params).grep(/COUNT/i)
  end

  def count_sql_for_relation(relation, scope_key)
    count_sql = nil
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      count_sql = payload[:sql].squish if payload[:sql].to_s.match?(/COUNT/i)
    end

    pagination = nil
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      pagination = RecordingStudioApi::Services::PaginateResourceCollection.call(
        relation: relation,
        resource: "folders",
        recordable_type: "Folder",
        limit: 50,
        pagination_token: nil,
        sort: nil,
        order: nil,
        api: :public,
        include_total: true,
        scope_key: "client:#{scope_key}"
      )
    end

    assert pagination.success?
    counted_total = pagination.value.response_body { |_rows, meta| meta.fetch(:total_count) }
    assert_equal 1, counted_total
    count_sql
  end

  def queries_for(params)
    queries = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s
      next if payload[:name] == "SCHEMA"

      queries << sql.squish
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      get "/recording_studio_api/api/v1/folders", params: params, headers: authorization_headers
    end
    assert_response :success
    queries
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
