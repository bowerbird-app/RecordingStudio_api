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
    RecordingStudio.configuration.authorize_write = method(:accessible_edit_write_allowed?)
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

  test "create handler rejects a page with no title" do
    error = assert_raises(ActiveRecord::RecordInvalid) do
      RecordingStudioApi::Services::ResourceOperations::Create.call(create_page_context(title: nil))
    end

    assert_includes error.message, "Title can't be blank"
    assert_equal 0, Page.where(title: [nil, ""]).count
  end

  private

  def accessible_edit_write_allowed?(actor:, action:, recording: nil, root_recording: nil, **)
    return false unless actor.is_a?(ActiveRecord::Base) && action.to_s.strip.present?

    target = recording || root_recording
    return false if target.nil?

    RecordingStudioAccessible.authorized?(actor: actor, recording: target, role: :edit)
  end

  def create_page_context(title:)
    api_client = RecordingStudioApi::ApiClient.create!(name: "Page writer", api_key: "public")
    grant = RecordingStudioApi::AccessGrant.new(
      api_client: api_client,
      credential: nil,
      access_recording: @access_recording,
      root_recording: @root_recording
    )
    params = { "parent_id" => @folder.id }
    params["title"] = title unless title.nil?

    RecordingStudioApi::ResourceOperationContext.new(
      recording: nil,
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
      parent_recording: @folder
    )
  end
end
