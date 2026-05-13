# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "../test_helper"
require_relative "../dummy/config/environment"

require "devise/test/integration_helpers"
require "rails/test_help"

class DocsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  TEST_PASSWORD = "DocsTestPassword!2026"

  setup do
    @user = User.find_or_create_by!(email: "docs-test@example.com") do |user|
      user.password = TEST_PASSWORD
      user.password_confirmation = TEST_PASSWORD
    end

    sign_in @user
  end

  test "install page renders successfully" do
    get docs_install_path
    assert_response :success
    assert_select "h1", text: "Install"
    assert_includes response.body, "1. Add the gem"
    assert_includes response.body, "bundle add recording_studio_api"
    assert_includes response.body, "generate recording_studio_api:migrations"
    assert_includes response.body, "tailwindcss:build"
  end

  test "config page renders successfully" do
    get docs_config_path
    assert_response :success
    assert_select "h1", text: "Config"
    expected_copy = "Current config keys plus the constraints for the future HTTP API registries."

    assert_includes response.body, expected_copy
    assert_includes response.body, "RecordingStudioApi.configure do |config|"
    assert_includes response.body, "ENV[\"RECORDING_STUDIO_API_KEY\"]"
    assert_includes response.body, "Nested resource declarations should mirror the recording tree"
  end

  test "recordable types page renders configured recordables dynamically" do
    with_recordable_types([Workspace, "RecordingStudio::AccessBoundary"]) do
      summary_data = create_recordable_type_summary_data

      get docs_recordable_types_path
      response_text = response.body.gsub(/\s+/, " ").strip

      assert_response :success
      assert_select "h1", text: "Recordable types"
      assert_includes(
        response.body,
        "The list below comes directly from RecordingStudio.configuration.recordable_types."
      )
      assert_includes response.body, "Workspace"
      assert_includes response.body, "Access boundary"
      assert_includes response_text, summary_data[:workspace]
      assert_includes response_text, summary_data[:boundary]
    end
  end

  test "recordable types page includes dummy app defaults" do
    get docs_recordable_types_path

    assert_response :success
    assert_includes response.body, "Workspace"
    assert_includes response.body, "Folder"
    assert_includes response.body, "Page"
  end

  test "recordings tree page renders successfully" do
    workspace = Workspace.create!(name: "Tree Workspace")
    root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    folder = Folder.create!(name: "Reference")
    folder_recording = RecordingStudio::Recording.create!(recordable: folder, parent_recording: root_recording)
    page = Page.create!(title: "API")
    RecordingStudio::Recording.create!(recordable: page, parent_recording: folder_recording)
    access_boundary = RecordingStudio::AccessBoundary.create!(minimum_role: :edit)
    boundary_recording = RecordingStudio::Recording.create!(
      recordable: access_boundary,
      parent_recording: root_recording
    )
    access = RecordingStudio::Access.create!(actor: @user, role: :admin)
    RecordingStudio::Recording.create!(recordable: access, parent_recording: boundary_recording)

    get docs_recordings_tree_path

    assert_response :success
    assert_select "h1", text: "Recordings tree"
    assert_includes response.body, "Workspace: Tree Workspace"
    assert_includes response.body, "Folder: Reference"
    assert_includes response.body, "Page: API"
    assert_includes response.body, "Access boundary: Edit"
    assert_includes response.body, "Access: Admin for #{@user.email}"
    assert_select "ul.list-disc", minimum: 2
    refute_includes response.body, "Current structure"
    refute_includes response.body, "This tree is generated from RecordingStudio::Recording records"
  end

  test "gem_views page renders successfully" do
    get docs_gem_views_path
    assert_response :success
    assert_select "h1", text: "Gem Views"
    assert_includes response.body, "app/views/recording_studio_api/home/index.html.erb"
  end

  test "methods page renders successfully" do
    get docs_methods_path
    assert_response :success
    assert_select "h1", text: "Methods"
    assert_includes response.body, "Current public Ruby surface for configuration and engine orchestration."
    assert_includes response.body, "RecordingStudioApi.configure"
    assert_includes response.body, "RecordingStudioApi.configuration"
    assert_includes response.body, "The future HTTP DSL should build on this object"
  end

  test "sidebar includes documentation links" do
    get docs_install_path

    assert_select %(a[href="#{docs_install_path}"]), text: /Install/
    assert_select %(a[href="#{docs_config_path}"]), text: /Config/
    assert_select %(a[href="#{docs_recordable_types_path}"]), text: /Recordable types/
    assert_select %(a[href="#{docs_recordings_tree_path}"]), text: /Recordings tree/
    assert_select %(a[href="#{docs_gem_views_path}"]), text: /Gem Views/
    assert_select %(a[href="#{docs_methods_path}"]), text: /Methods/
  end

  private

  def with_recordable_types(recordable_types)
    original_recordable_types = RecordingStudio.configuration.recordable_types
    RecordingStudio.configuration.recordable_types = recordable_types
    yield
  ensure
    RecordingStudio.configuration.recordable_types = original_recordable_types
  end

  def create_recordable_type_summary_data
    workspace_recordings_before = RecordingStudio::Recording.where(recordable_type: "Workspace").count
    workspaces_before = Workspace.count
    boundary_recordings_before = RecordingStudio::Recording.where(
      recordable_type: "RecordingStudio::AccessBoundary"
    ).count
    boundaries_before = RecordingStudio::AccessBoundary.count

    workspace = Workspace.create!(name: "Counted Workspace")
    2.times { RecordingStudio::Recording.create!(recordable: workspace) }

    access_boundary = RecordingStudio::AccessBoundary.create!(minimum_role: :view)
    RecordingStudio::Recording.create!(recordable: access_boundary)

    {
      workspace: recordable_type_summary(
        workspace_recordings_before + 2,
        workspaces_before + 1,
        "recordings",
        "recordables"
      ),
      boundary: recordable_type_summary(
        boundary_recordings_before + 1,
        boundaries_before + 1,
        "recording",
        "recordable"
      )
    }
  end

  def recordable_type_summary(recording_count, recordable_count, recording_label, recordable_label)
    "#{recording_count} #{recording_label} point to this type " \
      "• #{recordable_count} #{recordable_label} in the database"
  end
end
