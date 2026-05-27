# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "../test_helper"
require_relative "../dummy/config/environment"

require "devise/test/integration_helpers"
require "rails/test_help"
require_relative "../support/api_dummy_helpers"

class MobileAppDemoControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!

    @user = create_user(email: "mobile-demo@example.com")
    sign_in @user
    @root_recording, @access_recording = create_access_recording_for(user: @user)
    create_page_recording(root_recording: @root_recording, page_title: "Mobile Demo Page")
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "show renders the mobile app demo page" do
    get mobile_app_demo_path

    assert_response :success
    assert_select "h1", text: "Mobile app demo"
    assert_includes response.body, "Login with mobile app demo"
    assert_not_includes response.body, "Demo client"
  end

  test "login flow exchanges code and shows API preview" do
    post start_mobile_app_demo_path
    assert_redirected_to(%r{/recording_studio_api/oauth/authorize})

    follow_redirect!
    assert_response :redirect

    follow_redirect!
    assert_redirected_to mobile_app_demo_path

    follow_redirect!
    assert_response :success
    assert_includes response.body, "Mobile app login completed. The demo token now has live API access."
    assert_includes response.body, "Refresh demo token"
    assert_includes response.body, "Revoke demo session"
    assert_includes response.body, "Oauth session access token"
    assert_includes response.body, "Oauth refresh token"
    assert_not_includes response.body, "Demo client"
    assert_not_includes response.body, "API scope preview"
  end
end