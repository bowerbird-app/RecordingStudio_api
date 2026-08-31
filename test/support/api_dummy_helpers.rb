# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "../test_helper"
require_relative "../dummy/config/environment"
require "rails/test_help"

module ApiDummyHelpers # rubocop:disable Metrics/ModuleLength
  TEST_PASSWORD = "ApiAuthPassword!2026"

  def with_access_creation_context(&)
    if defined?(RecordingStudioAccessible::AccessCreationContext)
      RecordingStudioAccessible::AccessCreationContext.allow(&)
    else
      yield
    end
  end

  def reset_recording_studio_api_configuration!
    configuration = RecordingStudioApi::Configuration.new
    # Deterministic tests: disable unauthenticated rate limits and open public management auth.
    configuration.rate_limit_oauth_enabled = false
    configuration.rate_limit_api_pre_auth_enabled = false
    configuration.rate_limit_api_enabled = false
    configuration.rate_limit_fail_closed = false
    configuration.api_management_authorization_required = false
    RecordingStudioApi.instance_variable_set(:@configuration, configuration)
    RecordingStudioApi::Concerns::RateLimiting.reset_redis_client!
    RecordingStudioApi::Admin::Queries::AdminApiCredentialsQuery.clear_cache!
    RecordingStudioApi::ApiRequestLogBatch.clear!
    RecordingStudioApi.register_default_capability_actions!
    RecordingStudioApi.register_default_resource_actions!
    register_dummy_capability_actions!
    register_dummy_recordable_type_apis!
  end

  def configure_dummy_operations_api!
    RecordingStudioApi.configuration.api(:operations) do |api|
      api.openapi_title = "Recording Studio Operations API"
      api.openapi_description = "Read-only operational access for trusted administrators and automation."
      api.documentation_enabled = true
      api.documentation_access = lambda do |controller:, actor:, api:|
        root_recording = controller.send(:current_root_recording)
        controller.send(:admin_root_current?) && RecordingStudioApi::Admin::ApiAuthorization.authorized?(
          actor: actor,
          api: api,
          root_recording: root_recording,
          role: RecordingStudioApi.configuration.access_management_view_role,
          create: true
        )
      end
      api.default_access = :read_only
      api.api_management_authorization_required = true
    end
    return if RecordingStudioApi.recordable_registration_for("AdminRoot", api: :operations)

    RecordingStudioApi.register_recordable_type_api(
      "AdminRoot",
      api: :operations,
      operations: %i[index show],
      serializer: ->(recordable, **) { { name: recordable.name } },
      output_keys: %i[name]
    )
  end

  def reset_recording_studio_capabilities!
    configuration = RecordingStudio.configuration
    configuration.instance_variable_set(:@capabilities, {})
    configuration.instance_variable_set(:@capability_options, {})
    RecordingStudio.enable_capability(:accessible, on: "Workspace")
    RecordingStudio.enable_capability(:accessible, on: "Folder")
    RecordingStudio.enable_capability(:accessible, on: "Page")
    RecordingStudio.enable_capability(:accessible, on: "AdminRoot") if defined?(AdminRoot)
    RecordingStudio.enable_capability(:api_access_point, on: "Workspace")
    RecordingStudio.enable_capability(:api_access_point, on: "Folder")
    RecordingStudio.enable_capability(:api_access_point, on: "AdminRoot") if defined?(AdminRoot)
    RecordingStudio.enable_capability(:movable, on: "Folder")
  end

  def create_user(email: "api-user-#{SecureRandom.hex(4)}@example.com")
    User.find_or_create_by!(email: email) do |user|
      user.password = TEST_PASSWORD
      user.password_confirmation = TEST_PASSWORD
    end
  end

  def create_admin_root_recording(name: "Admin")
    ensure_admin_root_tables!
    admin_root = AdminRoot.find_or_create_by!(name: name)

    [admin_root, RecordingStudio::Recording.find_or_create_by!(recordable: admin_root)]
  end

  def ensure_admin_root_tables!
    connection = ActiveRecord::Base.connection

    unless connection.table_exists?(:admin_roots)
      connection.create_table :admin_roots, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
        t.string :name, null: false

        t.timestamps
      end
    end

    return if connection.table_exists?(:admin_sections)

    connection.create_table :admin_sections, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :key, null: false
      t.string :name, null: false

      t.timestamps
    end
    connection.add_index :admin_sections, :key, unique: true
  end

  def create_access_recording_for(user:, workspace_name: "Workspace #{SecureRandom.hex(4)}", role: :admin)
    Current.actor = user
    Current.impersonator = nil if defined?(Current) && Current.respond_to?(:impersonator=)
    workspace = Workspace.create!(name: workspace_name)
    root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    access_recording = grant_or_bootstrap_access!(
      recording: root_recording,
      actor: user,
      role: role
    )

    [root_recording, access_recording]
  end

  def create_page_recording(root_recording:, parent_recording: nil, folder_name: "Folder #{SecureRandom.hex(4)}", page_title: "Page #{SecureRandom.hex(4)}")
    parent_recording ||= root_recording
    folder = Folder.create!(name: folder_name)
    folder_recording = RecordingStudio::Recording.create!(recordable: folder, parent_recording: parent_recording)
    page = Page.create!(title: page_title)

    RecordingStudio::Recording.create!(recordable: page, parent_recording: folder_recording)
  end

  def create_oauth_client(name: "Demo App", confidential: false, redirect_uris: ["http://127.0.0.1/callback"], api: :public)
    attrs = {
      name: name,
      client_id: RecordingStudioApi::OauthClientSecret.generate_client_id,
      confidential: confidential,
      redirect_uris: redirect_uris,
      api_key: RecordingStudioApi.configuration.fetch_api(api).name
    }
    secret_token = nil
    if confidential
      secret = RecordingStudioApi::OauthClientSecret.generate
      attrs[:client_secret_digest] = secret.fetch(:digest)
      secret_token = secret.fetch(:token)
    end

    [RecordingStudioApi::OauthClient.create!(attrs), secret_token]
  end

  def pkce_pair
    verifier = "V#{SecureRandom.urlsafe_base64(32)}"
    verifier = verifier.ljust(43, "a")
    {
      verifier: verifier,
      challenge: RecordingStudioApi::Pkce.s256_challenge(verifier)
    }
  end

  def approve_delegated_oauth(oauth_client:, user:, access_recording:, role: "view", redirect_uri: "http://127.0.0.1/callback", pkce: nil)
    pkce ||= pkce_pair
    result = RecordingStudioApi::Services::CreateOauthAuthorization.call(
      oauth_client: oauth_client,
      manager_actor: user,
      access_recording: access_recording,
      role: role,
      redirect_uri: redirect_uri,
      code_challenge: pkce.fetch(:challenge),
      code_challenge_method: "S256"
    )
    raise result.error unless result.success?

    result.value.merge(pkce: pkce, redirect_uri: redirect_uri)
  end

  def issue_oauth_access_token_for(access_recording:, name: "OAuth client")
    payload = provision_api_client_for(access_recording: access_recording, name: name)

    token_result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: payload.fetch(:credential).oauth_client_id,
      client_secret: payload.fetch(:token)
    )

    raise token_result.error unless token_result.success?

    token_result.value.fetch(:access_token)
  end

  def provision_api_client_for(access_recording:, name: "OAuth client")
    provision_result = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_point_recording: access_point_recording_for(access_recording),
      manager_actor: access_manager_for(access_recording),
      role: access_recording.recordable.role,
      name: name
    )

    raise provision_result.error unless provision_result.success?

    provision_result.value
  end

  def access_point_recording_for(access_recording)
    access_recording.parent_recording || access_recording.root_recording
  end

  def access_manager_for(access_recording)
    access_point_recording = access_point_recording_for(access_recording)
    actor = access_recording.recordable.actor

    return actor if RecordingStudioApi::AccessManagementPolicy.new(actor: actor).can_manage_recording?(access_point_recording)

    manager = create_user(email: "api-access-manager-#{SecureRandom.hex(4)}@example.com")
    grant_or_bootstrap_access!(
      recording: access_point_recording,
      actor: manager,
      role: RecordingStudioApi.configuration.access_management_edit_role
    )
    manager
  end

  def create_access_recording(parent_recording:, user:, role:)
    grant_or_bootstrap_access!(recording: parent_recording, actor: user, role: role)
  end

  def grant_or_bootstrap_access!(recording:, actor:, role:)
    existing = RecordingStudioAccessible.access_recordings_for_actor(
      recording: recording,
      actor: actor
    ).first
    return existing if existing.present? && existing.recordable.role.to_s == role.to_s

    result = RecordingStudioAccessible.grant_access(
      recording: recording,
      actor: actor,
      role: role,
      manager_actor: actor
    )
    return result.value if result.success?

    if role.to_s == "admin"
      bootstrap = RecordingStudioAccessible.bootstrap_owner_access!(recording: recording, actor: actor)
      return bootstrap.value if bootstrap.success?
    end

    with_access_creation_context do
      access = RecordingStudio::Access.create!(actor: actor, role: role)
      RecordingStudio::Recording.create!(recordable: access, parent_recording: recording)
    end
  end

  def register_dummy_recordable_type_apis!
    RecordingStudioApi.register_recordable_type_api(
      "Workspace",
      serializer: ->(recordable, **) { { name: recordable.name } },
      output_keys: %i[name],
      sortable_attributes: %i[name],
      writable_attributes: %i[name],
      openapi: {
        details_schema: {
          type: "object",
          properties: {
            name: { type: "string", description: "Workspace attributes." }
          },
          required: ["name"]
        }
      }
    )

    RecordingStudioApi.register_recordable_type_api(
      "Folder",
      serializer: ->(recordable, **) { { name: recordable.name } },
      output_keys: %i[name],
      sortable_attributes: %i[name],
      writable_attributes: %i[name],
      capability_actions: %i[move],
      openapi: {
        details_schema: {
          type: "object",
          properties: {
            name: { type: "string", description: "Folder attributes." }
          },
          required: ["name"]
        }
      }
    )
  end

  def register_dummy_capability_actions!; end
end
