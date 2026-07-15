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

  private

  def remove_credential!
    credential = @payload.fetch(:credential)
    credential.delete
  end

  def query(status: nil)
    params = {}
    params[:status] = status if status
    context = Context.new(params: params, current_actor: @user, root_recording: @root_recording)

    RecordingStudioApi::Admin::Queries::ApiAccessClientsQuery.call(context)
  end
end