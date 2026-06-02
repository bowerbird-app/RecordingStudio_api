# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/recording_studio_api/services/resource_operations/base"
require_relative "../../lib/recording_studio_api/services/trashable_operations/restore"

class TrashableOperationsRestoreTest < ActiveSupport::TestCase
  ApiClient = Struct.new(:id)
  Credential = Struct.new(:id)

  class RestoreableRecording
    attr_reader :calls

    def restore!(**kwargs)
      @calls = kwargs
    end

    def recordable_type
      "Page"
    end
  end

  class RestoreableRecordable
    attr_reader :calls

    def restore!(**kwargs)
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

    def recordable
      Object.new
    end

    def recordable_type
      "Page"
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
    def recordable
      Object.new
    end

    def recordable_type
      "Workspace"
    end

    # rubocop:disable Naming/PredicatePrefix
    def has_attribute?(_name)
      false
    end
    # rubocop:enable Naming/PredicatePrefix
  end

  class NoKeywordTarget
    attr_reader :called

    def restore
      @called = true
      :ok
    end
  end

  def service
    @service ||= RecordingStudioApi::Services::TrashableOperations::Restore.new(context)
  end

  def context
    @context ||= RecordingStudioApi::ResourceOperationContext.new(
      recording: nil,
      recordable_type: "Page",
      resource_name: "pages",
      api_client: ApiClient.new(11),
      credential: Credential.new(22),
      access_recording: nil,
      access_grant: nil,
      root_recording: nil,
      params: {},
      scoped_recordings: nil
    )
  end

  test "restore_resource uses recording restore method with restore metadata" do
    recording = RestoreableRecording.new

    service.send(:restore_resource!, recording)

    assert_equal "restore", recording.calls.fetch(:metadata).fetch(:api_action)
    assert_equal 11, recording.calls.fetch(:actor).id
    assert_equal 22, recording.calls.fetch(:metadata).fetch(:api_credential_id)
  end

  test "restore_resource uses recordable restore method when recording does not implement restore" do
    recordable = RestoreableRecordable.new
    recording = RecordingWithRecordable.new(recordable)

    service.send(:restore_resource!, recording)

    assert_equal 11, recordable.calls.fetch(:actor).id
    assert_equal 22, recordable.calls.fetch(:metadata).fetch(:api_credential_id)
  end

  test "restore_resource clears trashed_at and raises unsupported errors when needed" do
    recording = RecordingWithTrashedAt.new

    service.send(:restore_resource!, recording)
    assert_equal({ trashed_at: nil }, recording.updated_attributes)

    error = assert_raises(RecordingStudioApi::UnsupportedActionError) do
      service.send(:restore_resource!, UnsupportedRecording.new)
    end

    assert_includes error.message, "Restore is not supported"
  end

  test "invoke_resource_method falls back when keyword arguments are not accepted" do
    target = NoKeywordTarget.new

    result = service.send(:invoke_resource_method, target, :restore, actor: ApiClient.new(9))

    assert_equal :ok, result
    assert_equal true, target.called
  end
end