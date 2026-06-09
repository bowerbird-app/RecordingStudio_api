# frozen_string_literal: true

require_relative "support/api_dummy_helpers"
require "securerandom"

class IntegrationTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user)

    @payload = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: @access_recording,
      name: "Integration API client"
    ).value

    token_result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: @payload.fetch(:credential).oauth_client_id,
      client_secret: @payload.fetch(:token)
    )

    @access_token = token_result.value.fetch(:access_token)
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "builds access grant from authorization header" do
    result = RecordingStudioApi.access_grant_from_authorization_header(
      authorization_header: "Bearer #{@access_token}"
    )

    assert result.success?, result.error
    grant = result.value
    assert_instance_of RecordingStudioApi::AccessGrant, grant
    assert_equal @payload.fetch(:access_recording).id, grant.access_recording.id
    assert_equal @root_recording.id, grant.root_recording.id
    assert_equal @payload.fetch(:api_client).id, grant.actor.id
  end

  test "resolves access recording selection for actors" do
    resolution = RecordingStudioApi.resolve_access_recording_for_actor(actor: @user)

    assert_nil resolution.fetch(:error)
    assert_equal @access_recording.id, resolution.fetch(:recording).id

    invalid_resolution = RecordingStudioApi.resolve_access_recording_for_actor(
      actor: @user,
      requested_access_recording_id: SecureRandom.uuid
    )

    assert_equal :invalid_access_recording, invalid_resolution.fetch(:error)
    assert_nil invalid_resolution.fetch(:recording)
  end
end
