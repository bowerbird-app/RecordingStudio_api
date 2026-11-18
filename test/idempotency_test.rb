# frozen_string_literal: true

require "redis"
require_relative "support/api_dummy_helpers"

class IdempotencyTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    @previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    Rails.cache = @previous_cache
  end

  test "replay returns the first success for the same action, recording, and input" do
    calls = 0

    RecordingStudioApi::IdempotencyStore.stub(:redis, nil) do
      first = replay(input: { "b" => 1, "a" => 2 }) do
        calls += 1
        { json: { "id" => "rec-1" }, status: :created }
      end
      second = replay(input: { "a" => 2, "b" => 1 }) do
        calls += 1
        { json: { "id" => "rec-2" }, status: :created }
      end

      assert_equal({ "id" => "rec-1" }, first.fetch(:json))
      assert_equal :created, first.fetch(:status)
      assert_equal "rec-1", second.dig(:json, "id")
      assert_equal 1, calls
    end
  end

  test "replay refuses the same key when the input changes" do
    calls = 0

    RecordingStudioApi::IdempotencyStore.stub(:redis, nil) do
      replay(input: { "name" => "A" }) do
        calls += 1
        { json: { "id" => "rec-1" }, status: :created }
      end
      error = assert_raises(RecordingStudioApi::InvalidActionInputError) do
        replay(input: { "name" => "B" }) do
          calls += 1
          { json: { "id" => "rec-2" }, status: :created }
        end
      end

      assert_equal 1, calls
      assert_equal "Idempotency-Key was already used with different input", error.message
    end
  end

  test "replay runs again for another recording or another action" do
    calls = 0
    run = lambda do
      calls += 1
      { json: { "id" => "rec-#{calls}" }, status: :created }
    end

    RecordingStudioApi::IdempotencyStore.stub(:redis, nil) do
      replay(recording_id: "parent-1", action: "mint", input: { "name" => "A" }, &run)
      replay(recording_id: "parent-2", action: "mint", input: { "name" => "A" }, &run)
      replay(recording_id: "parent-1", action: "attach", input: { "name" => "A" }, &run)
    end

    assert_equal 3, calls
  end

  test "replay without input returns the first response when the body differs" do
    calls = 0

    RecordingStudioApi::IdempotencyStore.stub(:redis, nil) do
      replay do
        calls += 1
        { json: { "id" => "first" }, status: :created }
      end
      second = replay do
        calls += 1
        { json: { "id" => "second" }, status: :created }
      end

      assert_equal 1, calls
      assert_equal "first", second.dig(:json, "id")
    end
  end

  test "a blank key runs the block and stores nothing" do
    calls = 0

    RecordingStudioApi::IdempotencyStore.stub(:redis, nil) do
      2.times do
        replay(key: "") do
          calls += 1
          { json: { "id" => calls }, status: :created }
        end
      end
    end

    assert_equal 2, calls
  end

  test "a failed result is not replayed" do
    calls = 0

    RecordingStudioApi::IdempotencyStore.stub(:redis, nil) do
      replay(input: { "name" => "A" }) do
        calls += 1
        { json: { "id" => "nope" }, status: :unprocessable_entity }
      end
      replay(input: { "name" => "A" }) do
        calls += 1
        { json: { "id" => "yes" }, status: :created }
      end
    end

    assert_equal 2, calls
  end

  test "client id uses the api client id or the actor" do
    client = Struct.new(:id).new(4)
    actor = Class.new do
      def self.polymorphic_name
        "User"
      end

      def id
        9
      end
    end.new

    assert_equal 4, RecordingStudioApi::Idempotency.client_id(api_client: client, actor: nil)
    assert_equal "actor:User:9", RecordingStudioApi::Idempotency.client_id(api_client: nil, actor: actor)
    assert_raises(RecordingStudioApi::AuthorizationError) do
      RecordingStudioApi::Idempotency.client_id(api_client: nil, actor: nil)
    end
  end

  private

  def replay(key: "same", action: "mint", recording_id: "rec-1", input: :omit, &)
    kwargs = { api: "public", client_id: "client-1", key: key, action: action, recording_id: recording_id }
    kwargs[:input] = input unless input == :omit
    RecordingStudioApi::Idempotency.replay(**kwargs, &)
  end
end
