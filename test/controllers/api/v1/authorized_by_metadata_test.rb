# frozen_string_literal: true

require "delegate"
require_relative "../../../support/api_dummy_helpers"
require_relative "../../../support/oauth_client_double"

class ApiV1AuthorizedByMetadataTest < ActionDispatch::IntegrationTest
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user, role: :edit)
    @folder = create_page_recording(root_recording: @root_recording).parent_recording
    @payload = provision_api_client_for(access_recording: @access_recording, name: "Boundary writer")
    @oauth_client = RecordingStudioOauth::OauthClient.find(@payload.fetch(:api_client).id)
    authorization = Struct.new(:manager_actor).new(@user)
    credential = OauthBoundaryCredential.new(@payload.fetch(:credential), api_client: @oauth_client, authorization: authorization)
    @oauth_token = register_delegated_oauth_access_token(
      credential: credential,
      token: delegated_oauth_access_token
    )
    RecordingStudioApi.register_endpoint(
      :who,
      http_verb: :get,
      path: "who",
      handler: lambda { |context|
        {
          actor_type: defined?(Current) ? Current.actor&.class&.name : nil,
          actor_id: defined?(Current) ? Current.actor&.id : nil,
          authorized_by_type: context.authorized_by&.class&.name,
          authorized_by_id: context.authorized_by&.id
        }
      }
    )
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "oauth write records authorized_by and keeps the oauth client as actor" do
    patch "/recording_studio_api/api/v1/folders/#{@folder.id}",
          params: {
            name: "OAuth renamed folder",
            authorized_by_type: "Spoof",
            authorized_by_id: "spoof-symbol",
            "authorized_by_type" => "Spoof",
            "authorized_by_id" => "spoof-string"
          },
          headers: { "Authorization" => "Bearer #{@oauth_token}" }

    assert_response :success
    event = latest_update_event(@folder)
    assert_equal "RecordingStudioOauth::OauthClient", event.actor_type
    assert_equal @oauth_client.id, event.actor_id
    assert_nil event.impersonator_id
    assert_equal "User", event.metadata["authorized_by_type"]
    assert_equal @user.id, event.metadata["authorized_by_id"]

    get "/recording_studio_api/api/v1/who", headers: { "Authorization" => "Bearer #{@oauth_token}" }

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "User", payload.fetch("authorized_by_type")
    assert_equal @user.id, payload.fetch("authorized_by_id")
    assert_equal @payload.fetch(:access_recording).recordable.actor.class.name, payload.fetch("actor_type")
    assert_equal @payload.fetch(:access_recording).recordable.actor.id, payload.fetch("actor_id")
    assert_not_equal @user.id, payload.fetch("actor_id")
  end

  test "api key write leaves event metadata unchanged" do
    token = issue_oauth_access_token_for(access_recording: @access_recording, name: "Plain key")

    patch "/recording_studio_api/api/v1/folders/#{@folder.id}",
          params: {
            name: "Key renamed folder",
            authorized_by_type: "Spoof",
            authorized_by_id: "spoof-symbol"
          },
          headers: { "Authorization" => "Bearer #{token}" }

    assert_response :success
    event = latest_update_event(@folder)
    assert_equal "RecordingStudioApi::ApiClient", event.actor_type
    assert_nil event.impersonator_id
    assert_nil event.metadata["authorized_by_type"]
    assert_nil event.metadata["authorized_by_id"]

    get "/recording_studio_api/api/v1/who", headers: { "Authorization" => "Bearer #{token}" }

    assert_response :success
    payload = JSON.parse(response.body)
    assert_nil payload.fetch("authorized_by_type")
    assert_nil payload.fetch("authorized_by_id")
  end

  test "oauth delete leaves stored authorized_by metadata unchanged" do
    patch "/recording_studio_api/api/v1/folders/#{@folder.id}",
          params: { name: "Named before delete" },
          headers: { "Authorization" => "Bearer #{@oauth_token}" }
    assert_response :success
    stored = latest_update_event(@folder).metadata
    page = create_page_recording(root_recording: @root_recording)

    delete "/recording_studio_api/api/v1/pages/#{page.id}",
           headers: { "Authorization" => "Bearer #{@oauth_token}" }

    assert_response :success
    assert_equal "destroyed", JSON.parse(response.body).fetch("deleted_via")
    assert_equal stored, latest_update_event(@folder).metadata
    assert_nil RecordingStudio::Event.where(recording_id: page.id).where("metadata ? :key", key: "authorized_by_type").first
  end

  private

  def latest_update_event(recording)
    RecordingStudio::Event.where(recording_id: recording.id, action: "updated").order(occurred_at: :desc, created_at: :desc).first
  end

  class OauthBoundaryCredential < SimpleDelegator
    def initialize(credential, api_client:, authorization:)
      super(credential)
      @api_client = api_client
      @authorization = authorization
    end

    attr_reader :api_client, :authorization

    def oauth_authorization
      authorization
    end
  end
end
