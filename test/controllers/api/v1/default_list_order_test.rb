# frozen_string_literal: true

require_relative "../../../support/api_dummy_helpers"

class ApiV1DefaultListOrderTest < ActionDispatch::IntegrationTest
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user, role: :edit)
    @access_token = issue_oauth_access_token_for(access_recording: @access_recording, name: "Default order token")
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "orders a collection by the registered column and lets an explicit sort win" do
    bravo = create_folder_recording(root_recording: @root_recording, name: "Bravo")
    alpha = create_folder_recording(root_recording: @root_recording, name: "Alpha")
    zulu = create_folder_recording(root_recording: @root_recording, name: "Zulu")
    bravo.update_columns(created_at: 1.day.ago, updated_at: Time.current)
    alpha.update_columns(created_at: 3.days.ago, updated_at: Time.current)
    zulu.update_columns(created_at: 2.days.ago, updated_at: Time.current)
    register_folder_order({ name: :asc })

    get "/recording_studio_api/api/v1/folders", headers: authorization_headers

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal([alpha.id, bravo.id, zulu.id], payload.fetch("records").map { |row| row.fetch("id") })
    assert_equal "name", payload.dig("meta", "sort")
    assert_equal "asc", payload.dig("meta", "order")

    created_ids = page_ids("/recording_studio_api/api/v1/folders", limit: 1, sort: "created_at", order: "desc")
    assert_equal [bravo.id, zulu.id, alpha.id], created_ids
  end

  test "breaks column ties with id and keeps that order across pages" do
    first = create_folder_recording(root_recording: @root_recording, name: "Same")
    second = create_folder_recording(root_recording: @root_recording, name: "Same")
    timestamp = Time.current
    [first, second].each { |recording| recording.update_columns(created_at: timestamp, updated_at: timestamp) }
    register_folder_order({ name: :asc })
    recordings = RecordingStudio::Recording.table_name
    quoted_type = RecordingStudio::Recording.connection.quote("Folder")
    expected = RecordingStudio::Recording.where(id: [first.id, second.id])
                                         .joins(<<~SQL.squish)
                                           INNER JOIN folders recordable_sort_folders
                                             ON recordable_sort_folders.id = #{recordings}.recordable_id
                                            AND #{recordings}.recordable_type = #{quoted_type}
                                         SQL
                                         .order(Arel.sql("recordable_sort_folders.name ASC, #{recordings}.id ASC"))
                                         .pluck(:id)

    assert_equal expected, page_ids("/recording_studio_api/api/v1/folders", limit: 1)
  end

  test "orders by an associated position inside the authorized scope" do
    early = create_folder_recording(root_recording: @root_recording, name: "Later name")
    late = create_folder_recording(root_recording: @root_recording, name: "Earlier name")
    tied = create_folder_recording(root_recording: @root_recording, name: "Tied name")
    other_root, = create_access_recording_for(user: create_user(email: "hidden-position@example.com"))
    hidden = create_folder_recording(root_recording: other_root, name: "Hidden first")

    with_section_positions do |connection|
      insert_position(connection, early, 2)
      insert_position(connection, late, 1)
      insert_position(connection, tied, 2)
      insert_position(connection, hidden, 0)
      register_position_order

      expected = RecordingStudio::Recording.where(id: [early.id, late.id, tied.id])
                                           .joins(position_join_sql)
                                           .order(Arel.sql("section_positions.position ASC, #{RecordingStudio::Recording.table_name}.id ASC"))
                                           .pluck(:id)

      assert_equal expected, page_ids("/recording_studio_api/api/v1/folders", limit: 1)
      assert_not_includes expected, hidden.id

      get "/recording_studio_api/api/v1/folders/#{hidden.id}", headers: authorization_headers
      assert_response :not_found
      assert_equal "Resource was not found in this API scope", JSON.parse(response.body).dig("error", "message")
    end
  end

  test "keeps an out of scope row out of a column ordered list and leaves 403 and 404 in place" do
    middle = create_folder_recording(root_recording: @root_recording, name: "Middle")
    zulu = create_folder_recording(root_recording: @root_recording, name: "Zulu")
    other_root, = create_access_recording_for(user: create_user(email: "hidden-column@example.com"))
    hidden = create_folder_recording(root_recording: other_root, name: "Alpha")
    register_folder_order({ name: :asc })

    get "/recording_studio_api/api/v1/folders", headers: authorization_headers

    assert_response :success
    assert_equal([middle.id, zulu.id], JSON.parse(response.body).fetch("records").map { |row| row.fetch("id") })

    get "/recording_studio_api/api/v1/folders/#{hidden.id}", headers: authorization_headers
    assert_response :not_found
    assert_equal "Resource was not found in this API scope", JSON.parse(response.body).dig("error", "message")

    view_root, view_access = create_access_recording_for(user: create_user(email: "view-order@example.com"), role: :view)
    view_folder = create_folder_recording(root_recording: view_root, name: "Viewable")
    view_headers = { "Authorization" => "Bearer #{issue_oauth_access_token_for(access_recording: view_access, name: 'View order')}" }

    get "/recording_studio_api/api/v1/folders", headers: view_headers
    assert_response :success
    assert_equal([view_folder.id], JSON.parse(response.body).fetch("records").map { |row| row.fetch("id") })

    patch "/recording_studio_api/api/v1/folders/#{view_folder.id}", params: { name: "Blocked" }, headers: view_headers
    assert_response :forbidden
    assert_equal "API access grant is not authorized for this capability", JSON.parse(response.body).dig("error", "message")
  end

  test "rejects order without sort when the default order is a callable" do
    create_folder_recording(root_recording: @root_recording, name: "Only")
    register_position_order

    get "/recording_studio_api/api/v1/folders", params: { order: "desc" }, headers: authorization_headers

    assert_response :unprocessable_entity
    assert_equal "order requires sort when this resource uses a computed default order", JSON.parse(response.body).dig("error", "message")
  end

  test "rejects a default order column that is not on the recordable or the recording" do
    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.register_recordable_type_api("Folder", default_order: { missing: :asc })
    end

    assert_includes error.message, "missing"
  end

  private

  def authorization_headers
    { "Authorization" => "Bearer #{@access_token}" }
  end

  def register_folder_order(column_order)
    RecordingStudioApi.register_recordable_type_api("Folder", default_order: column_order)
  end

  def register_position_order
    RecordingStudioApi.register_recordable_type_api(
      "Folder",
      default_order: lambda { |scope|
        scope.unscope(:where).joins(position_join_sql).reorder(Arel.sql("section_positions.position ASC"))
      }
    )
  end

  def position_join_sql
    recordings = RecordingStudio::Recording.table_name
    <<~SQL.squish
      LEFT OUTER JOIN section_positions
        ON section_positions.recording_id = #{recordings}.id
    SQL
  end

  def create_folder_recording(root_recording:, name:)
    folder = Folder.create!(name: name)
    RecordingStudio::Recording.create!(recordable: folder, parent_recording: root_recording)
  end

  def page_ids(path, **params)
    ids = []
    token = nil

    10.times do
      get path, params: params.merge(pagination_token: token).compact, headers: authorization_headers
      assert_response :success, response.body
      payload = JSON.parse(response.body)
      ids.concat(payload.fetch("records").map { |row| row.fetch("id") })
      token = payload.dig("meta", "next_pagination_token")
      break if token.blank?
    end

    ids
  end

  def with_section_positions
    connection = ActiveRecord::Base.connection
    connection.drop_table(:section_positions, if_exists: true)
    connection.create_table(:section_positions, temporary: true, id: false) do |table|
      table.uuid :recording_id, null: false
      table.integer :position, null: false
    end
    yield connection
  ensure
    ActiveRecord::Base.connection.drop_table(:section_positions, if_exists: true)
  end

  def insert_position(connection, recording, position)
    connection.execute(
      "INSERT INTO section_positions (recording_id, position) VALUES (#{connection.quote(recording.id)}, #{position.to_i})"
    )
  end
end
