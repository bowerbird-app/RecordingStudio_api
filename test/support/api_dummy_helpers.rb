# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "../test_helper"
require_relative "../dummy/config/environment"
require "rails/test_help"

module ApiDummyHelpers
  TEST_PASSWORD = "ApiAuthPassword!2026"

  def with_access_creation_context(&)
    if defined?(RecordingStudioAccessible::AccessCreationContext)
      RecordingStudioAccessible::AccessCreationContext.allow(&)
    else
      yield
    end
  end

  def reset_recording_studio_api_configuration!
    RecordingStudioApi.instance_variable_set(:@configuration, RecordingStudioApi::Configuration.new)
    RecordingStudioApi.register_default_capability_actions!
    RecordingStudioApi.register_default_resource_actions!
    register_dummy_capability_actions!
    register_dummy_recordable_type_apis!
  end

  def reset_recording_studio_capabilities!
    configuration = RecordingStudio.configuration
    configuration.instance_variable_set(:@capabilities, {})
    configuration.instance_variable_set(:@capability_options, {})
    RecordingStudio.enable_capability(:accessible, on: "Workspace")
    RecordingStudio.enable_capability(:accessible, on: "Folder")
    RecordingStudio.enable_capability(:accessible, on: "Page")
    RecordingStudio.enable_capability(:accessible, on: "AdminRoot") if defined?(AdminRoot)
    RecordingStudio.enable_capability(:movable, on: "Folder")
    RecordingStudio.enable_capability(:trashable, on: "Page")
  end

  def create_user(email: "api-user-#{SecureRandom.hex(4)}@example.com")
    User.find_or_create_by!(email: email) do |user|
      user.password = TEST_PASSWORD
      user.password_confirmation = TEST_PASSWORD
    end
  end

  def create_admin_root_recording(name: "Admin")
    ensure_admin_root_tables!
    admin_root = AdminRoot.find_or_create_by!(name: name)

    [admin_root, RecordingStudio::Recording.find_or_create_by!(recordable: admin_root)]
  end

  def ensure_admin_root_tables!
    connection = ActiveRecord::Base.connection

    unless connection.table_exists?(:admin_roots)
      connection.create_table :admin_roots, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
        t.string :name, null: false

        t.timestamps
      end
    end

    return if connection.table_exists?(:admin_sections)

    connection.create_table :admin_sections, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :key, null: false
      t.string :name, null: false

      t.timestamps
    end
    connection.add_index :admin_sections, :key, unique: true
  end

  def create_access_recording_for(user:, workspace_name: "Workspace #{SecureRandom.hex(4)}", role: :admin)
    Current.actor = user
    Current.impersonator = nil if defined?(Current) && Current.respond_to?(:impersonator=)
    workspace = Workspace.create!(name: workspace_name)
    root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    access_recording = with_access_creation_context do
      access = RecordingStudio::Access.create!(actor: user, role: role)
      RecordingStudio::Recording.create!(recordable: access, parent_recording: root_recording)
    end

    [root_recording, access_recording]
  end

  def create_page_recording(root_recording:, parent_recording: nil, folder_name: "Folder #{SecureRandom.hex(4)}", page_title: "Page #{SecureRandom.hex(4)}")
    parent_recording ||= root_recording
    folder = Folder.create!(name: folder_name)
    folder_recording = RecordingStudio::Recording.create!(recordable: folder, parent_recording: parent_recording)
    page = Page.create!(title: page_title)

    RecordingStudio::Recording.create!(recordable: page, parent_recording: folder_recording)
  end

  def issue_oauth_access_token_for(access_recording:, name: "OAuth client")
    payload = provision_api_client_for(access_recording: access_recording, name: name)

    token_result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: payload.fetch(:credential).oauth_client_id,
      client_secret: payload.fetch(:token)
    )

    raise token_result.error unless token_result.success?

    token_result.value.fetch(:access_token)
  end

  def provision_api_client_for(access_recording:, name: "OAuth client")
    provision_result = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_point_recording: access_point_recording_for(access_recording),
      manager_actor: access_manager_for(access_recording),
      role: access_recording.recordable.role,
      name: name
    )

    raise provision_result.error unless provision_result.success?

    provision_result.value
  end

  def access_point_recording_for(access_recording)
    access_recording.parent_recording || access_recording.root_recording
  end

  def access_manager_for(access_recording)
    access_point_recording = access_point_recording_for(access_recording)
    actor = access_recording.recordable.actor

    return actor if RecordingStudioApi::AccessManagementPolicy.new(actor: actor).can_manage_recording?(access_point_recording)

    manager = create_user(email: "api-access-manager-#{SecureRandom.hex(4)}@example.com")
    with_access_creation_context do
      access = RecordingStudio::Access.create!(
        actor: manager,
        role: RecordingStudioApi.configuration.access_management_edit_role
      )
      RecordingStudio::Recording.create!(recordable: access, parent_recording: access_point_recording)
    end
    manager
  end

  def register_dummy_recordable_type_apis!
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      serializer: ->(recordable) { { name: recordable.name } },
      sortable_attributes: %i[name],
      openapi: {
        details_schema: {
          type: "object",
          properties: {
            name: { type: "string", description: "Workspace attributes." }
          },
          required: ["name"]
        }
      }
    )

    RecordingStudioApi.register_recordable_type_api(
      "Folder",
      serializer: ->(recordable) { { name: recordable.name } },
      sortable_attributes: %i[name],
      openapi: {
        details_schema: {
          type: "object",
          properties: {
            name: { type: "string", description: "Folder attributes." }
          },
          required: ["name"]
        }
      }
    )
  end

  def register_dummy_capability_actions!
    RecordingStudioApi.register_capability_action(
      :trash,
      capability: :trashable,
      http_verb: :post,
      handler: ->(context) { Dummy::Api::Actions::TrashRecording.call(context) },
      openapi: {
        summary: "Trash",
        description: "Soft-delete a trashable resource and return the updated recording payload."
      }
    ) unless RecordingStudioApi.capability_action(:trash)
  end
end
