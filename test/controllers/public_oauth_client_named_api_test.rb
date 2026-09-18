# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"

class PublicOauthClientNamedApiTest < ActionDispatch::IntegrationTest
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    RecordingStudioApi.configuration.api(:wp_plugin_demo)
    RecordingStudioApi.register_default_resource_actions!(api: :wp_plugin_demo)
    RecordingStudioApi.register_recordable_type_api(
      "Page",
      api: :wp_plugin_demo,
      operations: %i[index show],
      serializer: ->(recordable, **) { { title: recordable.title } },
      output_keys: %i[title]
    )
    RecordingStudioApi.register_recordable_type_api(
      "Page",
      operations: %i[index show],
      serializer: ->(recordable, **) { { title: recordable.title } },
      output_keys: %i[title]
    )

    user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: user)
    @page_recording = create_page_recording(root_recording: @root_recording)
    @payload = provision_api_client_for(access_recording: @access_recording, name: "Public registered app")
    @delegated_token = delegated_oauth_access_token
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "public oauth client bearer succeeds on named api pages after authorization_code" do
    register_delegated_oauth_access_token(credential: @payload.fetch(:credential), token: @delegated_token)
    register_authorization_code_grant!(@delegated_token)

    post "/recording_studio_api/apis/wp_plugin_demo/oauth/token", params: {
      grant_type: "authorization_code",
      code: "demo-code",
      client_id: "public-app",
      redirect_uri: "https://example.com/wp-admin/admin.php?page=recording-studio-connect"
    }

    assert_response :success
    access_token = JSON.parse(response.body).fetch("access_token")
    assert_equal @delegated_token, access_token

    get "/recording_studio_api/apis/wp_plugin_demo/v1/pages", headers: bearer_headers(access_token)

    assert_response :success
    records = JSON.parse(response.body).fetch("records")
    assert_includes records.map { |record| record.fetch("id") }, @page_recording.id
  end

  test "confidential oauth client bound to public still fails on the named api" do
    register_delegated_oauth_access_token(
      credential: @payload.fetch(:credential),
      token: @delegated_token,
      public_client: false
    )
    register_authorization_code_grant!(@delegated_token)

    post "/recording_studio_api/apis/wp_plugin_demo/oauth/token", params: {
      grant_type: "authorization_code",
      code: "demo-code",
      client_id: "confidential-app"
    }

    assert_response :success
    access_token = JSON.parse(response.body).fetch("access_token")

    get "/recording_studio_api/apis/wp_plugin_demo/v1/pages", headers: bearer_headers(access_token)

    assert_response :unauthorized
    assert_equal "authentication_failed", JSON.parse(response.body).dig("error", "code")
    assert_equal "Bearer access token is invalid", JSON.parse(response.body).dig("error", "message")
  end

  test "client_credentials public api key still fails on the named api" do
    access_token = issue_oauth_access_token_for(access_recording: @access_recording, name: "Machine public client")

    get "/recording_studio_api/apis/wp_plugin_demo/v1/pages", headers: bearer_headers(access_token)

    assert_response :unauthorized
    assert_equal "authentication_failed", JSON.parse(response.body).dig("error", "code")
    assert_equal "Bearer access token is invalid", JSON.parse(response.body).dig("error", "message")
  end

  private

  def register_authorization_code_grant!(access_token)
    RecordingStudioApi.register_oauth_grant(
      "authorization_code",
      handler: lambda do |**|
        RecordingStudioApi::Services::BaseService::Result.new(
          success: true,
          value: {
            access_token: access_token,
            token_type: "Bearer",
            expires_in: 3600
          }
        )
      end
    )
  end

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
