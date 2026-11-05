# frozen_string_literal: true

require_relative "support/api_dummy_helpers"

class AuthorizedWriteGateTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "dummy authorizer allows users and api clients when an action is present" do
    authorizer = RecordingStudio.configuration.authorize_write

    assert authorizer
    assert authorizer.call(actor: @user, action: "created")
    assert authorizer.call(actor: RecordingStudioApi::ApiClient.new(name: "Bot", api_key: "public"), action: "updated")
    refute authorizer.call(actor: @user, action: "")
    refute authorizer.call(actor: @user, action: "   ")
    refute authorizer.call(actor: nil, action: "created")
    refute authorizer.call(actor: Object.new, action: "created")
  end

  test "provision rotate token and update writes keep an explicit actor" do
    _root_recording, access_recording = create_access_recording_for(user: @user)
    payload = provision_api_client_for(access_recording: access_recording, name: "Write client")
    api_client = payload.fetch(:api_client)

    token_result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: payload.fetch(:credential).oauth_client_id,
      client_secret: payload.fetch(:token)
    )
    assert token_result.success?, token_result.error

    rotate_result = RecordingStudioApi::Services::RotateApiCredential.call(
      api_client: api_client,
      actor: @user
    )
    assert rotate_result.success?, rotate_result.error

    created_ids = RecordingStudio::Event.where(action: "created").pluck(:actor_id)
    assert_includes created_ids, api_client.id
  end
end
