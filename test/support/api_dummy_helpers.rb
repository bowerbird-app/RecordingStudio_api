# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "../test_helper"
require_relative "../dummy/config/environment"
require "rails/test_help"

module ApiDummyHelpers
  TEST_PASSWORD = "ApiAuthPassword!2026"

  def reset_recording_studio_api_configuration!
    RecordingStudioApi.instance_variable_set(:@configuration, RecordingStudioApi::Configuration.new)
    register_dummy_recordable_type_apis!
  end

  def reset_recording_studio_capabilities!
    configuration = RecordingStudio.configuration
    configuration.instance_variable_set(:@capabilities, {})
    configuration.instance_variable_set(:@capability_options, {})
  end

  def create_user(email: "api-user-#{SecureRandom.hex(4)}@example.com")
    User.find_or_create_by!(email: email) do |user|
      user.password = TEST_PASSWORD
      user.password_confirmation = TEST_PASSWORD
    end
  end

  def create_access_recording_for(user:, workspace_name: "Workspace #{SecureRandom.hex(4)}", role: :admin)
    Current.actor = user
    Current.impersonator = nil if defined?(Current) && Current.respond_to?(:impersonator=)
    workspace = Workspace.create!(name: workspace_name)
    root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    access = RecordingStudio::Access.create!(actor: user, role: role)
    access_recording = RecordingStudio::Recording.create!(recordable: access, parent_recording: root_recording)

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
    payload = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: access_recording,
      name: name
    ).value

    token_result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: payload.fetch(:credential).oauth_client_id,
      client_secret: payload.fetch(:token)
    )

    raise token_result.error unless token_result.success?

    token_result.value.fetch(:access_token)
  end

  def register_dummy_recordable_type_apis!
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      serializer: ->(recordable) { { name: recordable.name } },
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

    RecordingStudioApi.register_recordable_type_api(
      "Page",
      serializer: ->(recordable) { { title: recordable.title } },
      openapi: {
        details_schema: {
          type: "object",
          properties: {
            title: { type: "string", description: "Page attributes." }
          },
          required: ["title"]
        }
      }
    )
  end
end
