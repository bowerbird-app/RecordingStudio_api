# frozen_string_literal: true

require_relative "../../../support/api_dummy_helpers"
require_relative "../../../support/oauth_client_double"

class ApiV1WriteActorControllerTest < ActionDispatch::IntegrationTest
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user, role: :edit)
    @folder = create_page_recording(root_recording: @root_recording).parent_recording
    @channel_client = RecordingStudioApi::ApiClient.create!(name: "User OAuth app", api_key: "public")
    @oauth_client = RecordingStudioOauth::OauthClient.find(@channel_client.id)
    install_accessible_edit_write_policy!
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "a signed-in editor can update through a user OAuth token and provenance is recorded" do
    token = user_oauth_token(access_recording: @access_recording, manager: @user)

    patch "/recording_studio_api/api/v1/folders/#{@folder.id}",
          params: { name: "Renamed by the signed-in user" },
          headers: { "Authorization" => "Bearer #{token}" }

    assert_response :success
    assert_equal "Renamed by the signed-in user", @folder.reload.recordable.name
    event = latest_update_event(@folder)
    assert_equal @user, event.actor
    assert_equal @oauth_client, event.impersonator
  end

  test "a signed-in viewer is still denied" do
    view_user = create_user(email: "view-only-http-write-actor@example.com")
    view_root, view_access = create_access_recording_for(user: view_user, role: :view)
    folder = create_page_recording(root_recording: view_root).parent_recording
    install_accessible_edit_write_policy!
    token = user_oauth_token(access_recording: view_access, manager: view_user)

    patch "/recording_studio_api/api/v1/folders/#{folder.id}",
          params: { name: "Blocked over HTTP" },
          headers: { "Authorization" => "Bearer #{token}" }

    assert_response :forbidden
    assert_equal "API access grant is not authorized for this capability", JSON.parse(response.body).dig("error", "message")
    assert_not_equal "Blocked over HTTP", folder.reload.recordable.name
    assert_nil latest_update_event(folder)
  end

  private

  def install_accessible_edit_write_policy!
    RecordingStudio.configuration.authorize_write = method(:accessible_edit_write_allowed?)
  end

  def accessible_edit_write_allowed?(actor:, action:, recording: nil, root_recording: nil, **)
    return false unless actor.is_a?(ActiveRecord::Base) && action.to_s.strip.present?

    target = recording || root_recording
    return false if target.nil?

    RecordingStudioAccessible.authorized?(actor: actor, recording: target, role: :edit)
  end

  def user_oauth_token(access_recording:, manager:)
    authorization = Struct.new(:manager_actor).new(manager)
    credential = UserChannelCredential.new(
      api_client: @oauth_client,
      access_recording: access_recording,
      authorization: authorization
    )
    register_delegated_oauth_access_token(
      credential: credential,
      token: delegated_oauth_access_token
    )
  end

  def latest_update_event(recording)
    RecordingStudio::Event.where(recording_id: recording.id, action: "updated").order(occurred_at: :desc, created_at: :desc).first
  end

  class UserChannelCredential
    def initialize(api_client:, access_recording:, authorization:)
      @api_client = api_client
      @access_recording = access_recording
      @authorization = authorization
    end

    attr_reader :api_client, :authorization

    def oauth_authorization
      authorization
    end

    def effective_access_recording
      @access_recording
    end

    def effective_access_recording_id
      @access_recording.id
    end

    def active_for_authentication?
      true
    end

    def last_used_at
      nil
    end

    def update_column(*)
      nil
    end

    def revoke_tokens_on_expiry!(*); end
  end
end
