# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "../test_helper"
require_relative "../dummy/config/environment"
require_relative "../support/api_dummy_helpers"

class ApiAccessClientsQueryTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  Context = Struct.new(:params, :current_actor, :root_recording, keyword_init: true)

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user)
    @payload = provision_api_client_for(access_recording: @access_recording, name: "Credential-free client")
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "returns a missing row for a visible API client without credentials" do
    remove_credential!

    rows = query(status: "missing")

    assert_equal 1, rows.size

    row = rows.first
    assert_equal @payload.fetch(:api_client).id, row.id
    assert_equal @payload.fetch(:api_client), row.api_client
    assert_nil row.api_credential
    assert_equal 0, row.credentials_count
    assert_equal "No credentials", row.status
    assert_equal "No credentials", row.expires_text
    assert_equal 0, row.request_count
    assert_nil row.last_requested_at
  end

  test "does not include a credential-free client in the default active filter" do
    remove_credential!

    assert_empty query
  end

  test "scopes visible clients to the selected API" do
    RecordingStudioApi.configuration.api(:operations)
    RecordingStudioApi.register_recordable_type_api("Workspace", api: :operations)
    operations_payload = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_point_recording: @root_recording,
      manager_actor: @user,
      role: :admin,
      name: "Operations client",
      api: :operations
    ).value

    assert_equal [@payload.fetch(:api_client).id], query.map { |row| row.api_client.id }.uniq
    assert_equal [operations_payload.fetch(:api_client).id], query(api_key: "operations").map { |row| row.api_client.id }.uniq
  end

  private

  def remove_credential!
    credential = @payload.fetch(:credential)
    credential.delete
  end

  def query(status: nil, api_key: nil)
    params = {}
    params[:status] = status if status
    params[:api_key] = api_key if api_key
    context = Context.new(params: params, current_actor: @user, root_recording: @root_recording)

    RecordingStudioApi::Admin::Queries::ApiAccessClientsQuery.call(context)
  end
end