# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"
require "devise/test/integration_helpers"

class OauthAuthorizationsControllerTest < ActionDispatch::IntegrationTest
  include ApiDummyHelpers
  include Devise::Test::IntegrationHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user)
    @pkce = pkce_pair
    @oauth_client, = create_oauth_client
    sign_in @user
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "host-mounted authorize lists access then grants from the chosen node" do
    get "/recording_studio_api/oauth/authorize", params: authorize_params

    assert_response :success
    assert_select "body[data-recording-studio-default-layout='true']"
    assert_select "[role='listitem']"
    assert_includes response.body, @root_recording.recordable.name

    get "/recording_studio_api/oauth/authorize", params: authorize_params.merge(
      access_recording_id: @access_recording.id
    )

    assert_response :success
    assert_select "button[name='decision'][value='continue']"
    assert_select "button[name='decision'][value='cancel']"

    post "/recording_studio_api/oauth/authorize", params: authorize_params.merge(
      access_recording_id: @access_recording.id,
      role: "view",
      decision: "continue"
    )

    assert_response :redirect
    assert_match(/\Arsapi_ac_/, URI.decode_www_form(URI.parse(response.redirect_url).query.to_s).to_h.fetch("code"))
  end

  private

  def authorize_params
    {
      response_type: "code",
      client_id: @oauth_client.client_id,
      redirect_uri: "http://127.0.0.1/callback",
      state: "xyz",
      code_challenge: @pkce.fetch(:challenge),
      code_challenge_method: "S256"
    }
  end
end
