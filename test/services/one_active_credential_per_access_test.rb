# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"

class OneActiveCredentialPerAccessTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user)
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "a second active credential under the same access grant is rejected" do
    first_client = record_client_under(@access_recording, "First client")
    second_client = record_client_under(@access_recording, "Second client")
    create_credential_for(first_client)

    error = assert_raises(ActiveRecord::RecordInvalid) { create_credential_for(second_client) }

    assert_includes error.message, "already has an active credential"
    assert_equal 1, RecordingStudioApi::ApiCredential.where(revoked_at: nil).where(api_client_id: [first_client.id, second_client.id]).count
  end

  test "an expired credential still holds the access grant's active slot" do
    first_client = record_client_under(@access_recording, "Expired client")
    second_client = record_client_under(@access_recording, "Waiting client")
    create_credential_for(first_client, expires_at: 1.day.ago)

    error = assert_raises(ActiveRecord::RecordInvalid) { create_credential_for(second_client) }

    assert_includes error.message, "already has an active credential"
  end

  test "a revoked credential frees the access grant for another client" do
    first_client = record_client_under(@access_recording, "Revoked client")
    second_client = record_client_under(@access_recording, "Replacement client")
    create_credential_for(first_client, revoked_at: Time.current)

    credential = create_credential_for(second_client)

    assert_nil credential.revoked_at
    assert_equal @access_recording.id, second_client.access_recording.id
  end

  test "two access grants can each hold an active credential" do
    other_access = access_grant_for(create_user, @root_recording)
    first_client = record_client_under(@access_recording, "Grant A client")
    second_client = record_client_under(other_access, "Grant B client")

    create_credential_for(first_client)
    second = create_credential_for(second_client)

    assert_equal other_access.id, second_client.access_recording.id
    assert_nil second.revoked_at
  end

  test "a credential needs a recorded client under an access grant" do
    client = RecordingStudioApi::ApiClient.create!(name: "Unrecorded client")

    error = assert_raises(ActiveRecord::RecordInvalid) { create_credential_for(client) }

    assert_includes error.message, "must sit under an API client on an access grant"
  end

  private

  def record_client_under(access_recording, name)
    client = RecordingStudioApi::ApiClient.create!(name: "#{name} #{SecureRandom.hex(4)}")
    RecordingStudio.record!(
      action: "created",
      recordable: client,
      parent_recording: access_recording,
      root_recording: access_recording.root_recording,
      actor: @user
    )
    client
  end

  def access_grant_for(actor, parent_recording)
    with_access_creation_context do
      access = RecordingStudio::Access.create!(actor: actor, role: :admin)
      RecordingStudio::Recording.create!(recordable: access, parent_recording: parent_recording)
    end
  end

  def create_credential_for(client, revoked_at: nil, expires_at: 7.days.from_now)
    RecordingStudioApi::ApiCredential.create!(
      api_client: client,
      token_public_id: "pub_#{SecureRandom.hex(8)}",
      token_digest: "digest_#{SecureRandom.hex(16)}",
      token_prefix: "api",
      expires_at: expires_at,
      revoked_at: revoked_at
    )
  end
end

class OneActiveCredentialPerAccessConcurrencyTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  self.use_transactional_tests = false

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user, workspace_name: "Concurrent access #{SecureRandom.hex(4)}")
    @clients = [
      record_client_under(@access_recording, "Concurrent A"),
      record_client_under(@access_recording, "Concurrent B")
    ]
  end

  teardown do
    discard_created_rows!
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "two concurrent creates under one access grant keep a single active credential" do
    gate = Queue.new
    results = Queue.new
    threads = @clients.map do |client|
      client_id = client.id
      Thread.new do
        Rails.application.executor.wrap do
          gate.pop
          live_client = RecordingStudioApi::ApiClient.find(client_id)
          RecordingStudioApi::ApiCredential.create!(
            api_client: live_client,
            token_public_id: "pub_#{SecureRandom.hex(8)}",
            token_digest: "digest_#{SecureRandom.hex(16)}",
            token_prefix: "api",
            expires_at: 7.days.from_now
          )
          results << :created
        rescue ActiveRecord::RecordInvalid => e
          results << e
        end
      end
    end

    @clients.size.times { gate << true }
    threads.each { |thread| assert thread.join(15), "credential create did not finish" }

    outcomes = @clients.size.times.map { results.pop }
    errors = outcomes.grep(ActiveRecord::RecordInvalid)

    assert_equal 1, outcomes.count(:created)
    assert_equal 1, errors.size
    assert_includes errors.first.message, "already has an active credential"
    assert_equal 1, RecordingStudioApi::ApiCredential.where(api_client_id: @clients.map(&:id), revoked_at: nil).count
  end

  private

  def record_client_under(access_recording, name)
    client = RecordingStudioApi::ApiClient.create!(name: "#{name} #{SecureRandom.hex(4)}")
    RecordingStudio.record!(
      action: "created",
      recordable: client,
      parent_recording: access_recording,
      root_recording: access_recording.root_recording,
      actor: @user
    )
    client
  end

  def discard_created_rows!
    client_ids = Array(@clients).map(&:id)
    credential_ids = RecordingStudioApi::ApiCredential.where(api_client_id: client_ids).pluck(:id)
    recording_ids = RecordingStudio::Recording.unscoped.where(root_recording_id: @root_recording&.id).pluck(:id)
    recording_ids |= [@root_recording.id] if @root_recording

    RecordingStudioApi::ApiAccessToken.where(api_credential_id: credential_ids).delete_all if credential_ids.any?
    RecordingStudioApi::ApiCredential.where(id: credential_ids).delete_all
    delete_recordings!(recording_ids)
    RecordingStudioApi::ApiClient.where(id: client_ids).delete_all
  end

  def delete_recordings!(ids)
    remaining = ids.compact.uniq
    20.times do
      break if remaining.empty?

      parents = RecordingStudio::Recording.unscoped.where(parent_recording_id: remaining).distinct.pluck(:parent_recording_id)
      leaves = remaining - parents
      break if leaves.empty?

      RecordingStudio::Event.where(recording_id: leaves).delete_all
      RecordingStudio::Recording.unscoped.where(id: leaves).delete_all
      remaining -= leaves
    end
  end
end
