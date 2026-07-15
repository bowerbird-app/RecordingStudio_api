# frozen_string_literal: true

require "test_helper"
require_relative "../../../support/api_dummy_helpers"

class ResourcesControllerPrivateTest < ActiveSupport::TestCase
  ApiClient = Struct.new(:id)
  ApiCredential = Struct.new(:id)

  class TrashableRecording
    attr_reader :calls

    def recordable_type
      "Page"
    end

    def trash!(**kwargs)
      @calls = kwargs
    end
  end

  class TrashableRecordable
    attr_reader :calls

    def trash!(**kwargs)
      @calls = kwargs
    end
  end

  class RecordingWithRecordable
    attr_reader :recordable

    def initialize(recordable)
      @recordable = recordable
    end

    def recordable_type
      "Page"
    end
  end

  class RecordingWithTrashedAt
    attr_reader :updated_attributes

    def recordable_type
      "Page"
    end

    def recordable
      Object.new
    end

    # rubocop:disable Naming/PredicatePrefix
    def has_attribute?(name)
      name == :trashed_at
    end
    # rubocop:enable Naming/PredicatePrefix

    def update!(attributes)
      @updated_attributes = attributes
    end
  end

  class UnsupportedRecording
    def recordable_type
      "Workspace"
    end

    def recordable
      Object.new
    end

    # rubocop:disable Naming/PredicatePrefix
    def has_attribute?(_name)
      false
    end
    # rubocop:enable Naming/PredicatePrefix
  end

  class DestroyableRecording
    attr_reader :recordable, :destroyed

    def initialize(recordable)
      @recordable = recordable
      @destroyed = false
    end

    def destroy!
      @destroyed = true
    end
  end

  class ReadOnlyRecordable
    attr_reader :destroy_attempted

    def persisted?
      true
    end

    def destroy!
      @destroy_attempted = true
      raise ActiveRecord::ReadOnlyRecord
    end
  end

  class KeywordSensitiveTarget
    def initialize
      @fallback_called = false
    end

    attr_reader :fallback_called

    def perform
      @fallback_called = true
      :ok
    end

    def with_kwargs(**kwargs)
      kwargs
    end
  end

  class TrashablePage
    def trash! = nil
  end

  class PlainPage
    def placeholder = nil
  end

  def controller
    @controller ||= RecordingStudioApi::Api::V1::ResourcesController.new
  end

  test "trash_resource uses recording trash method when available" do
    recording = TrashableRecording.new

    with_api_identity do
      result = controller.send(:trash_resource!, recording)

      assert_equal "trashed", result
      assert_equal "delete", recording.calls.fetch(:metadata).fetch(:api_action)
      assert_equal 11, recording.calls.fetch(:actor).id
      assert_equal 11, recording.calls.fetch(:metadata).fetch(:api_client_id)
      assert_equal 22, recording.calls.fetch(:metadata).fetch(:api_credential_id)
    end
  end

  test "trash_resource uses recordable trash method when recording does not implement trash" do
    recordable = TrashableRecordable.new
    recording = RecordingWithRecordable.new(recordable)

    with_api_identity do
      result = controller.send(:trash_resource!, recording)

      assert_equal "trashed", result
      assert_equal 11, recordable.calls.fetch(:actor).id
      assert_equal 22, recordable.calls.fetch(:metadata).fetch(:api_credential_id)
    end
  end

  test "trash_resource falls back to trashed_at update and raises for unsupported recordables" do
    recording = RecordingWithTrashedAt.new

    with_api_identity do
      result = controller.send(:trash_resource!, recording)

      assert_equal "trashed", result
      assert_kind_of Time, recording.updated_attributes.fetch(:trashed_at)

      error = assert_raises(RecordingStudioApi::UnsupportedActionError) do
        controller.send(:trash_resource!, UnsupportedRecording.new)
      end

      assert_includes error.message, "Delete is not supported"
    end
  end

  test "trashable_recordable_type checks class trash method and configured capability fallback" do
    assert_equal true, controller.send(:trashable_recordable_type?, "ResourcesControllerPrivateTest::TrashablePage")

    RecordingStudio.stub(:capability_enabled?, false) do
      assert_equal false, controller.send(:trashable_recordable_type?, "ResourcesControllerPrivateTest::PlainPage")
    end

    RecordingStudio.stub(:capability_enabled?, true) do
      assert_equal true, controller.send(:trashable_recordable_type?, "ResourcesControllerPrivateTest::PlainPage")
      assert_nil controller.send(:ensure_trashable_recordable_type!, "ResourcesControllerPrivateTest::PlainPage")
    end

    RecordingStudio.stub(:capability_enabled?, false) do
      error = assert_raises(RecordingStudioApi::UnsupportedActionError) do
        controller.send(:ensure_trashable_recordable_type!, "ResourcesControllerPrivateTest::PlainPage")
      end

      assert_includes error.message, "Trash is not supported"
    end
  end

  test "destroy_resource deletes recording and tolerates readonly recordable destruction" do
    recordable = ReadOnlyRecordable.new
    recording = DestroyableRecording.new(recordable)

    RecordingStudio::Recording.stub(:transaction, ->(&block) { block.call }) do
      controller.send(:destroy_resource!, recording)
    end

    assert_equal true, recording.destroyed
    assert_equal true, recordable.destroy_attempted
  end

  test "invoke_resource_method retries without kwargs and serialize_delete_result marks record deleted" do
    target = KeywordSensitiveTarget.new

    result = controller.send(:invoke_resource_method, target, :perform, actor: ApiClient.new(1))
    with_kwargs = controller.send(:invoke_delete_method, target, :with_kwargs, metadata: { source: "test" })
    payload = controller.send(:serialize_delete_result, { "id" => "123" }, deleted_via: "trashed")

    assert_equal :ok, result
    assert_equal true, target.fallback_called
    assert_equal({ metadata: { source: "test" } }, with_kwargs)
    assert_equal true, payload.fetch(:deleted)
    assert_equal "trashed", payload.fetch(:deleted_via)
  end

  private

  def with_api_identity(&block)
    controller.stub(:current_api_client, ApiClient.new(11)) do
      controller.stub(:current_api_credential, ApiCredential.new(22)) do
        block.call
      end
    end
  end
end