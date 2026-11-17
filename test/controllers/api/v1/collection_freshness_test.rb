# frozen_string_literal: true

require_relative "../../../support/api_dummy_helpers"

class ApiV1IncludedChildrenQueryTest < ActionDispatch::IntegrationTest
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user, role: :edit)
    @access_token = issue_oauth_access_token_for(access_recording: @access_recording, name: "Include token")
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
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "included children load from the page ids and do not walk the scope tree" do
    create_page_recording(root_recording: @root_recording, folder_name: "Listed")
    queries = capture_sql do
      get "/recording_studio_api/api/v1/workspaces", headers: authorization_headers
    end

    assert_response :success
    lateral = queries.select { |sql| sql.include?("LATERAL") }
    assert_equal 1, lateral.length
    assert_includes lateral.first, @root_recording.id
    refute_includes lateral.first, "scope_tree"
    refute(queries.any? { |sql| sql.match?(/MAX\(/) && sql.match?(/COUNT\(/) })
  end

  test "a default list does not count the scope" do
    create_page_recording(root_recording: @root_recording)
    queries = capture_sql do
      get "/recording_studio_api/api/v1/pages", params: { limit: 50 }, headers: authorization_headers
    end

    assert_response :success
    refute JSON.parse(response.body).fetch("meta").key?("total_count")
    refute(queries.any? { |sql| sql.match?(/COUNT\(/i) })
  end

  private

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
end
