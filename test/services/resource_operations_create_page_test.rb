# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"

class ResourceOperationsCreatePageTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user, role: :edit)
    @folder = create_page_recording(root_recording: @root_recording).parent_recording
    RecordingStudioAuthorizedWrites.install!
    RecordingStudioApi.register_recordable_type_api(
      "Page",
      serializer: ->(recordable, **) { { title: recordable.title } },
      output_keys: %i[title],
      writable_attributes: %i[title],
      openapi: {
        details_schema: {
          type: "object",
          properties: { title: { type: "string", minLength: 1 } },
          required: ["title"]
        }
      }
    )
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "non-column writable immutable field reaches create and is ignored on update" do
    RecordingStudioApi.register_recordable_type_api(
      "Page",
      writable_attributes: %i[title credit_id],
      immutable_fields: %i[credit_id],
      openapi: {
        details_schema: {
          type: "object",
          properties: {
            title: { type: "string", minLength: 1 },
            credit_id: { type: "string" }
          },
          required: ["title"]
        }
      }
    )

    error = assert_raises(ActiveModel::UnknownAttributeError) do
      RecordingStudioApi::Services::ResourceOperations::Create.call(
        create_page_context(title: "Named", extra: { "credit_id" => "cred-1" })
      )
    end
    assert_match(/credit_id/, error.message)

    page_recording = create_page_recording(root_recording: @root_recording)
    RecordingStudioApi::Services::ResourceOperations::Update.call(
      update_page_context(page_recording, extra: { "credit_id" => "cred-2", "title" => "Renamed" })
    )

    assert_equal "Renamed", page_recording.reload.recordable.title
  end

  test "create handler rejects a page with no title" do
    error = assert_raises(ActiveRecord::RecordInvalid) do
      RecordingStudioApi::Services::ResourceOperations::Create.call(create_page_context(title: nil))
    end

    assert_includes error.message, "Title can't be blank"
    assert_equal 0, Page.where(title: [nil, ""]).count
  end

  private

  def create_page_context(title:, extra: {})
    params = { "parent_id" => @folder.id }
    params["title"] = title unless title.nil?
    params.merge!(extra)
    page_context(recording: nil, params: params, parent_recording: @folder)
  end

  def update_page_context(recording, extra: {})
    page_context(recording: recording, params: extra, parent_recording: nil)
  end

  def page_context(recording:, params:, parent_recording:)
    api_client = RecordingStudioApi::ApiClient.create!(name: "Page writer", api_key: "public")
    grant = RecordingStudioApi::AccessGrant.new(
      api_client: api_client,
      credential: nil,
      access_recording: @access_recording,
      root_recording: @root_recording
    )

    RecordingStudioApi::ResourceOperationContext.new(
      recording: recording,
      recordable_type: "Page",
      resource_name: "pages",
      api_client: api_client,
      credential: nil,
      access_recording: @access_recording,
      access_grant: grant,
      root_recording: @root_recording,
      api_version: "v1",
      params: {},
      request_params: params,
      scoped_recordings: grant.accessible_recordings,
      parent_recording: parent_recording
    )
  end
end
