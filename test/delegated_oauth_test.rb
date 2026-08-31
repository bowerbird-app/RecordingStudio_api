# frozen_string_literal: true

require_relative "support/api_dummy_helpers"
require "devise/test/integration_helpers"

class DelegatedOauthTest < ActionDispatch::IntegrationTest
  include ApiDummyHelpers
  include Devise::Test::IntegrationHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    RecordingStudioApi::DelegatedOauthVoiding.install!
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

  test "client_credentials still issues a machine token" do
    payload = provision_api_client_for(access_recording: @access_recording, name: "Machine client")

    post "/recording_studio_api/oauth/token", params: {
      grant_type: "client_credentials",
      client_id: payload.fetch(:credential).oauth_client_id,
      client_secret: payload.fetch(:token)
    }

    assert_response :success
    body = JSON.parse(response.body)
    assert_match(/\Arsapi_at_/, body.fetch("access_token"))
    refute body.key?("refresh_token")
  end

  test "named API isolation still rejects a public machine token on operations" do
    configure_dummy_operations_api!
    payload = provision_api_client_for(access_recording: @access_recording, name: "Public machine")
    token = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: payload.fetch(:credential).oauth_client_id,
      client_secret: payload.fetch(:token)
    ).value.fetch(:access_token)

    result = RecordingStudioApi::Services::AuthenticateOauthAccessToken.call(
      authorization_header: "Bearer #{token}",
      api: :operations
    )

    assert result.failure?
    assert_equal "Bearer access token is invalid", result.error
  end

  test "machine credential revocation still inactivates outstanding tokens" do
    payload = provision_api_client_for(access_recording: @access_recording, name: "Revocable machine")
    issued = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: payload.fetch(:credential).oauth_client_id,
      client_secret: payload.fetch(:token)
    )
    payload.fetch(:credential).revoke!

    result = RecordingStudioApi::Services::AuthenticateOauthAccessToken.call(
      authorization_header: "Bearer #{issued.value.fetch(:access_token)}"
    )

    assert result.failure?
    assert_equal "Bearer access token is inactive", result.error
  end

  test "approve code token and permitted API request succeed" do
    get "/recording_studio_api/oauth/authorize", params: authorize_params

    assert_response :success
    assert_select "body[data-recording-studio-default-layout='true']", count: 1
    assert_select "title", text: /Approve access/
    assert_includes response.body, @oauth_client.name
    assert_includes response.body, "Choose the highest permission this app may use."
    assert_not_includes response.body, "Choose a workspace and the highest permission this app may use."
    assert_select "select[name='access_recording_id']", count: 0
    assert_select "input[name='access_recording_id'][type='hidden'][value=?]", @access_recording.id
    assert_select "select[name='role']"
    assert_not_includes response.body, "Select an option"
    assert_select "[data-controller='recording-studio-root-switchable--root-switch-dropdown']", count: 0
    assert_not_includes response.body, "Sign out"

    post "/recording_studio_api/oauth/authorize", params: authorize_params.merge(
      access_recording_id: @access_recording.id,
      role: "view",
      decision: "approve"
    )

    assert_response :redirect
    code = code_from_redirect
    assert_match(/\Arsapi_ac_/, code)

    post "/recording_studio_api/oauth/token", params: {
      grant_type: "authorization_code",
      client_id: @oauth_client.client_id,
      code: code,
      redirect_uri: "http://127.0.0.1/callback",
      code_verifier: @pkce.fetch(:verifier)
    }

    assert_response :success
    body = JSON.parse(response.body)
    access_token = body.fetch("access_token")
    assert_match(/\Arsapi_at_/, access_token)
    assert_match(/\Arsapi_rt_/, body.fetch("refresh_token"))

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}",
        headers: { "Authorization" => "Bearer #{access_token}" }

    assert_response :success
    assert_equal @root_recording.id, JSON.parse(response.body).fetch("id")
  end

  test "authorization code reuse fails and voids the grant" do
    approved = approve_delegated_oauth(
      oauth_client: @oauth_client,
      user: @user,
      access_recording: @access_recording,
      pkce: @pkce
    )
    token_params = {
      grant_type: "authorization_code",
      client_id: @oauth_client.client_id,
      code: approved.fetch(:code),
      redirect_uri: "http://127.0.0.1/callback",
      code_verifier: @pkce.fetch(:verifier)
    }

    first = RecordingStudioApi::Services::IssueOauthAccessToken.call(**token_params)
    assert first.success?, first.error

    second = RecordingStudioApi::Services::IssueOauthAccessToken.call(**token_params)
    assert second.failure?
    assert_equal "invalid_grant", second.error.fetch(:error)
    assert_not_nil approved.fetch(:authorization).reload.revoked_at
    assert_not_nil approved.fetch(:access_recording).reload.trashed_at
  end

  test "expired authorization code fails" do
    approved = approve_delegated_oauth(
      oauth_client: @oauth_client,
      user: @user,
      access_recording: @access_recording,
      pkce: @pkce
    )

    travel 11.minutes do
      result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
        grant_type: "authorization_code",
        client_id: @oauth_client.client_id,
        code: approved.fetch(:code),
        redirect_uri: "http://127.0.0.1/callback",
        code_verifier: @pkce.fetch(:verifier)
      )

      assert result.failure?
      assert_equal "invalid_grant", result.error.fetch(:error)
    end
  end

  test "invalid redirect uri fails at token exchange" do
    approved = approve_delegated_oauth(
      oauth_client: @oauth_client,
      user: @user,
      access_recording: @access_recording,
      pkce: @pkce
    )

    result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "authorization_code",
      client_id: @oauth_client.client_id,
      code: approved.fetch(:code),
      redirect_uri: "http://127.0.0.1/other",
      code_verifier: @pkce.fetch(:verifier)
    )

    assert result.failure?
    assert_equal "invalid_grant", result.error.fetch(:error)
  end

  test "PKCE S256 succeeds and missing PKCE on public client fails" do
    get "/recording_studio_api/oauth/authorize", params: authorize_params.except(:code_challenge, :code_challenge_method)

    assert_response :redirect
    assert_includes redirect_query.fetch("error"), "invalid_request"

    approved = approve_delegated_oauth(
      oauth_client: @oauth_client,
      user: @user,
      access_recording: @access_recording,
      pkce: @pkce
    )
    result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "authorization_code",
      client_id: @oauth_client.client_id,
      code: approved.fetch(:code),
      redirect_uri: "http://127.0.0.1/callback",
      code_verifier: @pkce.fetch(:verifier)
    )

    assert result.success?, result.error
  end

  test "wrong PKCE verifier fails" do
    approved = approve_delegated_oauth(
      oauth_client: @oauth_client,
      user: @user,
      access_recording: @access_recording,
      pkce: @pkce
    )

    result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "authorization_code",
      client_id: @oauth_client.client_id,
      code: approved.fetch(:code),
      redirect_uri: "http://127.0.0.1/callback",
      code_verifier: "x" * 43
    )

    assert result.failure?
    assert_equal "invalid_grant", result.error.fetch(:error)
  end

  test "cannot grant a role above the manager" do
    edit_user = create_user(email: "edit-oauth-manager@example.com")
    _edit_root, edit_access = create_access_recording_for(user: edit_user, role: :edit)
    RecordingStudioApi.configuration.access_management_edit_role = :edit
    sign_in edit_user

    post "/recording_studio_api/oauth/authorize", params: authorize_params.merge(
      access_recording_id: edit_access.id,
      role: "admin",
      decision: "approve"
    )

    assert_response :unprocessable_entity
    assert_includes response.body, "Requested role exceeds your access"
    assert_equal 0, RecordingStudioApi::OauthAuthorization.where(manager_actor: edit_user).count
  end

  test "access grant actor is the authorization not the user" do
    approved = approve_delegated_oauth(
      oauth_client: @oauth_client,
      user: @user,
      access_recording: @access_recording,
      role: "edit",
      pkce: @pkce
    )
    issued = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "authorization_code",
      client_id: @oauth_client.client_id,
      code: approved.fetch(:code),
      redirect_uri: "http://127.0.0.1/callback",
      code_verifier: @pkce.fetch(:verifier)
    )

    grant_result = RecordingStudioApi.access_grant_from_authorization_header(
      authorization_header: "Bearer #{issued.value.fetch(:access_token)}"
    )

    assert grant_result.success?, grant_result.error
    assert_instance_of RecordingStudioApi::OauthAuthorization, grant_result.value.actor
    assert_equal approved.fetch(:authorization).id, grant_result.value.actor.id
    refute_equal @user, grant_result.value.actor
  end

  test "insufficient accessible role returns 403" do
    approved = approve_delegated_oauth(
      oauth_client: @oauth_client,
      user: @user,
      access_recording: @access_recording,
      role: "view",
      pkce: @pkce
    )
    issued = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "authorization_code",
      client_id: @oauth_client.client_id,
      code: approved.fetch(:code),
      redirect_uri: "http://127.0.0.1/callback",
      code_verifier: @pkce.fetch(:verifier)
    )
    folder = Folder.create!(name: "Protected folder")
    folder_recording = RecordingStudio::Recording.create!(recordable: folder, parent_recording: @root_recording)

    patch "/recording_studio_api/api/v1/folders/#{folder_recording.id}",
          params: { name: "Renamed" },
          headers: { "Authorization" => "Bearer #{issued.value.fetch(:access_token)}" }

    assert_response :forbidden
  end

  test "manager removal voids the token and trashes oauth access" do
    token, authorization = delegated_access_token(role: "edit")

    @access_recording.update!(trashed_at: Time.current)

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}",
        headers: { "Authorization" => "Bearer #{token}" }

    assert_response :forbidden
    assert_not_nil authorization.reload.revoked_at
    assert_not_nil authorization.access_recording.reload.trashed_at
  end

  test "manager role drop below the grant voids the token and trashes oauth access" do
    token, authorization = delegated_access_token(role: "admin")

    RecordingStudioAccessible::AccessCreationContext.allow do
      RecordingStudio.root_recording_or_self(@access_recording).revise(@access_recording, actor: @user) do |access|
        access.role = :view
      end
    end

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}",
        headers: { "Authorization" => "Bearer #{token}" }

    assert_response :forbidden
    assert_not_nil authorization.reload.revoked_at
    assert_not_nil authorization.access_recording.reload.trashed_at
  end

  test "refresh token rotation issues a new token and rejects the old refresh token" do
    approved = approve_delegated_oauth(
      oauth_client: @oauth_client,
      user: @user,
      access_recording: @access_recording,
      pkce: @pkce
    )
    first = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "authorization_code",
      client_id: @oauth_client.client_id,
      code: approved.fetch(:code),
      redirect_uri: "http://127.0.0.1/callback",
      code_verifier: @pkce.fetch(:verifier)
    )
    old_refresh = first.value.fetch(:refresh_token)

    rotated = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "refresh_token",
      client_id: @oauth_client.client_id,
      refresh_token: old_refresh
    )

    assert rotated.success?, rotated.error
    new_access = rotated.value.fetch(:access_token)
    new_refresh = rotated.value.fetch(:refresh_token)
    refute_equal old_refresh, new_refresh

    get "/recording_studio_api/api/v1/workspaces/#{@root_recording.id}",
        headers: { "Authorization" => "Bearer #{new_access}" }
    assert_response :success

    replay = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "refresh_token",
      client_id: @oauth_client.client_id,
      refresh_token: old_refresh
    )
    assert replay.failure?
    assert_equal "invalid_grant", replay.error.fetch(:error)
  end

  test "revoked and expired refresh tokens fail" do
    approved = approve_delegated_oauth(
      oauth_client: @oauth_client,
      user: @user,
      access_recording: @access_recording,
      pkce: @pkce
    )
    issued = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "authorization_code",
      client_id: @oauth_client.client_id,
      code: approved.fetch(:code),
      redirect_uri: "http://127.0.0.1/callback",
      code_verifier: @pkce.fetch(:verifier)
    )
    refresh = issued.value.fetch(:refresh_token)
    stored = RecordingStudioApi::RefreshToken.find_by_token(
      RecordingStudioApi::OauthRefreshToken,
      refresh
    )
    stored.revoke!

    revoked = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "refresh_token",
      client_id: @oauth_client.client_id,
      refresh_token: refresh
    )
    assert revoked.failure?
    assert_equal "invalid_grant", revoked.error.fetch(:error)

    stored.update_columns(revoked_at: nil, expires_at: 1.second.ago, updated_at: Time.current)
    expired = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "refresh_token",
      client_id: @oauth_client.client_id,
      refresh_token: refresh
    )
    assert expired.failure?
    assert_equal "invalid_grant", expired.error.fetch(:error)
  end

  test "public delegated token is rejected on operations" do
    configure_dummy_operations_api!
    token, = delegated_access_token(role: "view")

    get "/recording_studio_api/apis/operations/v1/admin_roots",
        headers: { "Authorization" => "Bearer #{token}" }

    assert_response :unauthorized
  end

  test "discovery documents are valid" do
    get "/recording_studio_api/.well-known/oauth-authorization-server"

    assert_response :success
    metadata = JSON.parse(response.body)
    assert_equal "http://www.example.com/recording_studio_api", metadata.fetch("issuer")
    assert_equal "http://www.example.com/recording_studio_api/oauth/authorize", metadata.fetch("authorization_endpoint")
    assert_equal "http://www.example.com/recording_studio_api/oauth/token", metadata.fetch("token_endpoint")
    assert_includes metadata.fetch("grant_types_supported"), "authorization_code"
    assert_includes metadata.fetch("grant_types_supported"), "refresh_token"
    assert_includes metadata.fetch("grant_types_supported"), "client_credentials"
    assert_equal ["S256"], metadata.fetch("code_challenge_methods_supported")
    refute metadata.key?("mcp")

    get "/recording_studio_api/.well-known/oauth-protected-resource"

    assert_response :success
    resource = JSON.parse(response.body)
    assert_equal "http://www.example.com/recording_studio_api/api", resource.fetch("resource")
    assert_includes resource.fetch("authorization_servers"), metadata.fetch("issuer")
    assert_equal ["header"], resource.fetch("bearer_methods_supported")

    configure_dummy_operations_api!
    get "/recording_studio_api/apis/operations/.well-known/oauth-authorization-server"

    assert_response :success
    operations = JSON.parse(response.body)
    assert_includes operations.fetch("issuer"), "/apis/operations"
    assert_includes operations.fetch("token_endpoint"), "/apis/operations/oauth/token"
  end

  test "deny redirects to the client with access_denied" do
    assert_no_difference -> { RecordingStudioApi::OauthAuthorization.where(oauth_client: @oauth_client).count } do
      post "/recording_studio_api/oauth/authorize", params: authorize_params.merge(
        access_recording_id: @access_recording.id,
        role: "view",
        decision: "deny"
      )
    end

    assert_response :redirect
    query = redirect_query
    assert_equal "access_denied", query.fetch("error")
    assert_equal "xyz", query.fetch("state")
  end

  test "consent with several workspaces requires a choice" do
    second_root, = create_access_recording_for(user: @user, workspace_name: "Second workspace")

    get "/recording_studio_api/oauth/authorize", params: authorize_params

    assert_response :success
    assert_includes response.body, "Choose a workspace and the highest permission this app may use."
    assert_select "select[name='access_recording_id']"
    assert_select "select[name='access_recording_id'] option[value='']", count: 0
    assert_select "select[name='access_recording_id'] option", count: 2
    assert_includes response.body, @root_recording.recordable.name
    assert_includes response.body, second_root.recordable.name
    assert_not_includes response.body, "Select an option"
    assert_select "select[name='role']"
    assert_includes response.body, "Cannot be higher than your own access on that workspace."
  end

  test "approve without a workspace does not create an authorization" do
    create_access_recording_for(user: @user, workspace_name: "Second workspace")

    assert_no_difference -> { RecordingStudioApi::OauthAuthorization.where(oauth_client: @oauth_client).count } do
      post "/recording_studio_api/oauth/authorize", params: authorize_params.merge(
        role: "view",
        decision: "approve"
      )
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Choose a workspace"
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

  def code_from_redirect
    redirect_query.fetch("code")
  end

  def redirect_query
    URI.decode_www_form(URI.parse(response.redirect_url).query.to_s).to_h
  end

  def delegated_access_token(role:)
    approved = approve_delegated_oauth(
      oauth_client: @oauth_client,
      user: @user,
      access_recording: @access_recording,
      role: role,
      pkce: @pkce
    )
    issued = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "authorization_code",
      client_id: @oauth_client.client_id,
      code: approved.fetch(:code),
      redirect_uri: "http://127.0.0.1/callback",
      code_verifier: @pkce.fetch(:verifier)
    )
    raise issued.error unless issued.success?

    [issued.value.fetch(:access_token), approved.fetch(:authorization)]
  end
end
