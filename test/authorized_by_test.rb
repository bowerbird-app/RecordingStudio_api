# frozen_string_literal: true

require_relative "support/api_dummy_helpers"
require_relative "support/oauth_client_double"

class AuthorizedByTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user, role: :edit)
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
    Current.impersonator = nil if defined?(Current) && Current.respond_to?(:impersonator=)
  end

  test "resolves the oauth authorization manager and ignores api credentials" do
    authorization = Struct.new(:manager_actor).new(@user)
    oauth_credential = Object.new
    oauth_credential.define_singleton_method(:oauth_authorization) { authorization }
    token_record = Object.new
    token_record.define_singleton_method(:oauth_authorization) { authorization }

    assert_equal @user, RecordingStudioApi::AuthorizedBy.actor_for(credential: oauth_credential)
    assert_equal @user, RecordingStudioApi::AuthorizedBy.actor_for(credential: RecordingStudioApi::ApiCredential.new, token_record: token_record)
    assert_nil RecordingStudioApi::AuthorizedBy.actor_for(credential: RecordingStudioApi::ApiCredential.new)
    assert_nil RecordingStudioApi::AuthorizedBy.actor_for(credential: oauth_credential_with(manager: nil))
  end

  test "access grant uses an explicit human and does not invent one for api keys" do
    oauth_credential = oauth_credential_with(manager: @user)
    resolved = RecordingStudioApi::AccessGrant.new(
      api_client: nil,
      credential: oauth_credential,
      access_recording: nil
    )
    explicit_nil = RecordingStudioApi::AccessGrant.new(
      api_client: nil,
      credential: oauth_credential,
      access_recording: nil,
      authorized_by: nil
    )
    api_key = RecordingStudioApi::AccessGrant.new(
      api_client: nil,
      credential: RecordingStudioApi::ApiCredential.new,
      access_recording: nil
    )

    assert_equal @user, resolved.authorized_by
    assert_nil explicit_nil.authorized_by
    assert_nil api_key.authorized_by
  end

  test "action resource and endpoint contexts expose the grant human to callers that omit it" do
    credential = oauth_credential_with(manager: @user)
    grant = RecordingStudioApi::AccessGrant.new(api_client: nil, credential: credential, access_recording: nil)
    action_context = RecordingStudioApi::ActionContext.new(
      recording: nil,
      api_client: nil,
      credential: credential,
      access_recording: nil,
      access_grant: grant,
      root_recording: nil,
      params: {}
    )
    resource_context = RecordingStudioApi::ResourceOperationContext.new(
      recording: nil,
      recordable_type: "Folder",
      resource_name: "folders",
      api_client: nil,
      credential: credential,
      access_recording: nil,
      access_grant: grant,
      root_recording: nil,
      api_version: "v1",
      params: {},
      request_params: {},
      scoped_recordings: [],
      parent_recording: nil
    )
    endpoint_context = RecordingStudioApi::RegisteredEndpointContext.new(
      api_client: nil,
      credential: credential,
      access_recording: nil,
      access_grant: grant,
      root_recording: nil,
      params: {}
    )

    [action_context, resource_context, endpoint_context].each do |context|
      assert_equal @user, context.authorized_by
      merged = context.with_authorized_by(api_action: "move")
      assert_equal "move", merged[:api_action]
      assert_equal "User", merged[:authorized_by_type]
      assert_equal @user.id, merged[:authorized_by_id]
    end
  end

  test "oauth update keeps the oauth client as actor and records the authorizing human" do
    payload = provision_api_client_for(access_recording: @access_recording, name: "OAuth writer")
    oauth_client = oauth_client_for(payload.fetch(:api_client).id)
    folder = create_page_recording(root_recording: @root_recording).parent_recording
    Current.actor = @user
    Current.impersonator = nil if Current.respond_to?(:impersonator=)

    result = RecordingStudioApi::Services::ResourceOperations::Update.call(
      resource_context_for(payload, folder, api_client: oauth_client, human: @user, name: "Renamed by oauth")
    )

    assert_equal :ok, result.fetch(:status, :ok)
    event = latest_update_event(folder)
    assert_equal "RecordingStudioOauth::OauthClient", event.actor_type
    assert_equal oauth_client.id, event.actor_id
    assert_nil event.impersonator_id
    assert_nil event.impersonator_type
    assert_equal "User", event.metadata["authorized_by_type"]
    assert_equal @user.id, event.metadata["authorized_by_id"]
    assert_equal @user, Current.actor
    assert_nil Current.impersonator if Current.respond_to?(:impersonator)
    assert_equal "Renamed by oauth", folder.reload.recordable.name
  end

  test "api key update leaves event metadata without an authorizing human" do
    payload = provision_api_client_for(access_recording: @access_recording, name: "API key writer")
    folder = create_page_recording(root_recording: @root_recording).parent_recording

    RecordingStudioApi::Services::ResourceOperations::Update.call(
      resource_context_for(payload, folder, api_client: payload.fetch(:api_client), human: nil, name: "Renamed by key")
    )

    event = latest_update_event(folder)
    assert_equal payload.fetch(:api_client), event.actor
    assert_nil event.impersonator_id
    assert_nil event.metadata["authorized_by_type"]
    assert_nil event.metadata["authorized_by_id"]
    assert_equal({}, event.metadata)
  end

  test "move metadata keeps its own keys and adds the authorizing human" do
    payload = provision_api_client_for(access_recording: @access_recording, name: "Move writer")
    recording = MoveCapture.new
    destination = Object.new
    recordings = Object.new
    recordings.define_singleton_method(:find_by) { |id:| id == "destination" ? destination : nil }
    grant = Object.new
    human = @user
    grant.define_singleton_method(:authorize!) { |**| true }
    grant.define_singleton_method(:accessible_recordings) { recordings }
    grant.define_singleton_method(:authorized_by) { human }
    context = RecordingStudioApi::ActionContext.new(
      recording: recording,
      api_client: payload.fetch(:api_client),
      credential: payload.fetch(:credential),
      access_recording: payload.fetch(:access_recording),
      access_grant: grant,
      root_recording: @root_recording,
      params: { parent_id: "destination" }
    )

    assert_equal recording, RecordingStudioApi::Services::MoveRecording.call(context)

    metadata = recording.calls.fetch(0).fetch(:metadata)
    assert_equal payload.fetch(:api_client), recording.calls.fetch(0).fetch(:actor)
    assert_nil recording.calls.fetch(0)[:impersonator]
    assert_equal "move", metadata[:api_action]
    assert_equal payload.fetch(:api_client).id, metadata[:api_client_id]
    assert_equal payload.fetch(:credential).id, metadata[:api_credential_id]
    assert_equal "User", metadata[:authorized_by_type]
    assert_equal @user.id, metadata[:authorized_by_id]
  end

  private

  def oauth_credential_with(manager:)
    authorization = Struct.new(:manager_actor).new(manager)
    credential = Object.new
    credential.define_singleton_method(:oauth_authorization) { authorization }
    credential
  end

  def oauth_client_for(id)
    RecordingStudioOauth::OauthClient.find(id)
  end

  def resource_context_for(payload, folder, api_client:, human:, name:)
    credential = payload.fetch(:credential)
    if human
      authorization = Struct.new(:manager_actor).new(human)
      credential.define_singleton_method(:oauth_authorization) { authorization }
    end
    grant = RecordingStudioApi::AccessGrant.new(
      api_client: payload.fetch(:api_client),
      credential: credential,
      access_recording: payload.fetch(:access_recording),
      root_recording: @root_recording,
      authorized_by: human
    )
    RecordingStudioApi::ResourceOperationContext.new(
      recording: folder,
      recordable_type: "Folder",
      resource_name: "folders",
      api_client: api_client,
      credential: credential,
      access_recording: payload.fetch(:access_recording),
      access_grant: grant,
      root_recording: @root_recording,
      api_version: "v1",
      params: {},
      request_params: { "name" => name },
      scoped_recordings: grant.accessible_recordings,
      parent_recording: nil
    )
  end

  def latest_update_event(recording)
    RecordingStudio::Event.where(recording_id: recording.id, action: "updated").order(occurred_at: :desc, created_at: :desc).first
  end

  class MoveCapture
    def initialize
      @calls = []
    end

    attr_reader :calls

    def move_to!(**kwargs)
      @calls << kwargs
    end

    def reload
      self
    end
  end
end
