# frozen_string_literal: true

require_relative "../support/api_dummy_helpers"

class ResourceOperationsNilApiClientTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  PAGINATION_TOKEN_PURPOSE = "recording_studio_api.pagination.v2"

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
    @root_recording, @access_recording = create_access_recording_for(user: @user, role: :edit)
    @previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Current.actor = @user if defined?(Current)
  end

  teardown do
    Rails.cache = @previous_cache
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "create with an idempotency key and no api client stores one record and replays it" do
    key = "folder-create-#{SecureRandom.hex(8)}"
    attributes = { "name" => "Idempotent folder" }

    RecordingStudioApi::IdempotencyStore.stub(:redis, nil) do
      assert_difference("Folder.count", 1) do
        @first = RecordingStudioApi::Services::ResourceOperations::Create.call(
          resource_context(recordable_type: "Folder", resource_name: "folders", idempotency_key: key, attributes: attributes, parent_recording: @root_recording)
        )
      end

      assert_no_difference("Folder.count") do
        @second = RecordingStudioApi::Services::ResourceOperations::Create.call(
          resource_context(recordable_type: "Folder", resource_name: "folders", idempotency_key: key, attributes: attributes, parent_recording: @root_recording)
        )
      end
    end

    assert_equal :created, @first.fetch(:status)
    assert_equal :created, @second.fetch(:status)
    assert_equal stringify(@first.fetch(:json)), stringify(@second.fetch(:json))
    assert_equal "Idempotent folder", stringify(@first.fetch(:json)).fetch("name")
    assert_equal 1, Folder.where(name: "Idempotent folder").count

    cache_key = RecordingStudioApi::IdempotencyStore.redis_key(api: "public", client_id: actor_scope_key, key: key)
    assert Rails.cache.exist?(cache_key), cache_key
    assert_equal "recording_studio_api:idempotency:public:#{actor_scope_key}:#{Digest::SHA256.hexdigest(key)}", cache_key
  end

  test "index with no api client succeeds and paginates" do
    pages = Array.new(3) { |index| create_page_recording(root_recording: @root_recording, page_title: "Listed page #{index}") }
    now = Time.current
    pages.each { |page| page.update_columns(created_at: now, updated_at: now) }

    first = RecordingStudioApi::Services::ResourceOperations::Index.call(
      resource_context(recordable_type: "Page", resource_name: "pages", params: { limit: 2 })
    )
    first_body = stringify(first.fetch(:json))
    first_meta = first_body.fetch("meta")
    first_ids = first_body.fetch("records").map { |row| row.fetch("id") }

    assert_equal 2, first_meta.fetch("limit")
    assert_equal true, first_meta.fetch("has_more")
    token = first_meta.fetch("next_pagination_token")
    refute_nil token
    assert_equal actor_scope_key, pagination_scope(token)

    second = RecordingStudioApi::Services::ResourceOperations::Index.call(
      resource_context(recordable_type: "Page", resource_name: "pages", params: { limit: 2, pagination_token: token })
    )
    second_body = stringify(second.fetch(:json))
    second_meta = second_body.fetch("meta")
    second_ids = second_body.fetch("records").map { |row| row.fetch("id") }

    assert_equal false, second_meta.fetch("has_more")
    assert_nil second_meta.fetch("next_pagination_token")
    assert_equal pages.map(&:id).sort, (first_ids + second_ids).sort
    assert_empty(first_ids & second_ids)
  end

  test "api client idempotency and pagination keys stay on the client id" do
    api_client = RecordingStudioApi::ApiClient.create!(name: "Key stability", api_key: "public")
    key = "client-folder-#{SecureRandom.hex(8)}"
    pages = Array.new(3) { |index| create_page_recording(root_recording: @root_recording, page_title: "Client page #{index}") }
    now = Time.current
    pages.each { |page| page.update_columns(created_at: now, updated_at: now) }

    RecordingStudioApi::IdempotencyStore.stub(:redis, nil) do
      RecordingStudioApi::Services::ResourceOperations::Create.call(
        resource_context(
          recordable_type: "Folder",
          resource_name: "folders",
          idempotency_key: key,
          attributes: { "name" => "Client keyed folder" },
          parent_recording: @root_recording,
          api_client: api_client
        )
      )
    end

    client_cache_key = RecordingStudioApi::IdempotencyStore.redis_key(api: "public", client_id: api_client.id, key: key)
    actor_cache_key = RecordingStudioApi::IdempotencyStore.redis_key(api: "public", client_id: actor_scope_key, key: key)
    assert Rails.cache.exist?(client_cache_key)
    assert_not Rails.cache.exist?(actor_cache_key)

    listed = RecordingStudioApi::Services::ResourceOperations::Index.call(
      resource_context(recordable_type: "Page", resource_name: "pages", params: { limit: 2 }, api_client: api_client)
    )
    token = stringify(listed.fetch(:json)).dig("meta", "next_pagination_token")
    assert_equal "client:#{api_client.id}", pagination_scope(token)
  end

  test "another actor with the same idempotency key creates a new record" do
    key = "shared-folder-#{SecureRandom.hex(8)}"
    other_user = create_user(email: "other-actor-#{SecureRandom.hex(4)}@example.com")
    other_root, other_access = create_access_recording_for(user: other_user, role: :edit)

    RecordingStudioApi::IdempotencyStore.stub(:redis, nil) do
      assert_difference("Folder.count", 2) do
        @first = RecordingStudioApi::Services::ResourceOperations::Create.call(
          resource_context(
            recordable_type: "Folder",
            resource_name: "folders",
            idempotency_key: key,
            attributes: { "name" => "Folder for A" },
            parent_recording: @root_recording
          )
        )
        @second = RecordingStudioApi::Services::ResourceOperations::Create.call(
          resource_context(
            recordable_type: "Folder",
            resource_name: "folders",
            idempotency_key: key,
            attributes: { "name" => "Folder for B" },
            parent_recording: other_root,
            access_recording: other_access,
            root_recording: other_root
          )
        )
      end
    end

    first_body = stringify(@first.fetch(:json))
    second_body = stringify(@second.fetch(:json))
    assert_equal "Folder for A", first_body.fetch("name")
    assert_equal "Folder for B", second_body.fetch("name")
    refute_equal first_body.fetch("id"), second_body.fetch("id")
  end

  test "a list cursor issued to one actor is rejected for another" do
    3.times { |index| create_page_recording(root_recording: @root_recording, page_title: "Cursor page #{index}") }
    listed = RecordingStudioApi::Services::ResourceOperations::Index.call(
      resource_context(recordable_type: "Page", resource_name: "pages", params: { limit: 2 })
    )
    token = stringify(listed.fetch(:json)).dig("meta", "next_pagination_token")
    refute_nil token

    other_user = create_user(email: "cursor-actor-#{SecureRandom.hex(4)}@example.com")
    other_root, other_access = create_access_recording_for(user: other_user, role: :edit)

    error = assert_raises(RecordingStudioApi::InvalidPaginationTokenError) do
      RecordingStudioApi::Services::ResourceOperations::Index.call(
        resource_context(
          recordable_type: "Page",
          resource_name: "pages",
          params: { limit: 2, pagination_token: token },
          access_recording: other_access,
          root_recording: other_root
        )
      )
    end

    assert_equal "Pagination token does not match authenticated client", error.message
  end

  test "create and index raise when the grant has no api client and no actor" do
    key = "nobody-#{SecureRandom.hex(8)}"
    message = RecordingStudioApi::AuthorizationError::MISSING_REQUEST_PRINCIPAL

    assert_no_difference("Folder.count") do
      error = assert_raises(RecordingStudioApi::AuthorizationError) do
        RecordingStudioApi::Services::ResourceOperations::Create.call(
          resource_context(
            recordable_type: "Folder",
            resource_name: "folders",
            idempotency_key: key,
            attributes: { "name" => "Should not be stored" },
            parent_recording: @root_recording,
            access_recording: nil,
            root_recording: nil
          )
        )
      end
      assert_equal message, error.message
    end

    error = assert_raises(RecordingStudioApi::AuthorizationError) do
      RecordingStudioApi::Services::ResourceOperations::Index.call(
        resource_context(
          recordable_type: "Page",
          resource_name: "pages",
          access_recording: nil,
          root_recording: nil
        )
      )
    end
    assert_equal message, error.message

    paginator_error = assert_raises(RecordingStudioApi::AuthorizationError) do
      RecordingStudioApi::Services::PaginateResourceCollection.call(
        relation: RecordingStudio::Recording.none,
        resource: "pages",
        recordable_type: "Page",
        limit: 1,
        pagination_token: nil,
        sort: nil,
        order: nil,
        scope_key: nil
      )
    end
    assert_equal message, paginator_error.message
  end

  private

  def resource_context(recordable_type:, resource_name:, params: {}, attributes: nil, idempotency_key: nil, parent_recording: nil, api_client: nil, access_recording: @access_recording, root_recording: @root_recording)
    grant = RecordingStudioApi::AccessGrant.new(
      api_client: api_client,
      credential: nil,
      access_recording: access_recording,
      root_recording: root_recording
    )
    RecordingStudioApi::ResourceOperationContext.new(
      recording: nil,
      recordable_type: recordable_type,
      resource_name: resource_name,
      api_client: api_client,
      credential: nil,
      access_recording: access_recording,
      access_grant: grant,
      root_recording: root_recording,
      api_version: "v1",
      params: params,
      request_params: attributes || {},
      scoped_recordings: access_recording ? grant.accessible_recordings : RecordingStudio::Recording.none,
      parent_recording: parent_recording,
      idempotency_key: idempotency_key
    )
  end

  def actor_scope_key(user = @user)
    "actor:User:#{user.id}"
  end

  def stringify(payload)
    payload.deep_stringify_keys
  end

  def pagination_scope(token)
    Rails.application.message_verifier(PAGINATION_TOKEN_PURPOSE).verify(token, purpose: PAGINATION_TOKEN_PURPOSE).fetch("scope")
  end
end
