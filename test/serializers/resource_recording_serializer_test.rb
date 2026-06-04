# frozen_string_literal: true

require "test_helper"

module RecordingStudioApi
  module Serializers
    class ResourceRecordingSerializerTest < Minitest::Test
      RecordableStub = Struct.new(:id, :name, :title, :attributes, keyword_init: true)

      def setup
        @original_configuration_defined = RecordingStudioApi.instance_variable_defined?(:@configuration)
        @original_configuration = RecordingStudioApi.instance_variable_get(:@configuration)
        RecordingStudioApi.instance_variable_set(:@configuration, RecordingStudioApi::Configuration.new)
      end

      def teardown
        if @original_configuration_defined
          RecordingStudioApi.instance_variable_set(:@configuration, @original_configuration)
        elsif RecordingStudioApi.instance_variable_defined?(:@configuration)
          RecordingStudioApi.remove_instance_variable(:@configuration)
        end
      end

      def test_call_includes_default_recordable_attributes_when_no_custom_serializer_is_registered
        recording = build_recording(
          recordable_type: "Folder",
          recordable: RecordableStub.new(
            id: "folder-1",
            name: "Marketing",
            attributes: {
              "id" => "folder-1",
              "name" => "Marketing",
              "created_at" => Time.now,
              "updated_at" => Time.now
            }
          )
        )

        payload = ResourceRecordingSerializer.call(recording)

        refute payload.key?(:title)
        assert_equal({ "name" => "Marketing" }, payload.fetch(:attributes))
      end

      def test_call_merges_default_recordable_attributes_with_registered_serializer_attributes
        RecordingStudioApi.register_recordable_type_api(
          "Page",
          serializer: ->(recordable) { { summary: "Summary: #{recordable.title}" } }
        )

        recording = build_recording(
          recordable_type: "Page",
          recordable: RecordableStub.new(
            id: "page-1",
            title: "Docs Landing",
            attributes: {
              "id" => "page-1",
              "title" => "Docs Landing",
              "content" => "Hello world"
            }
          )
        )

        payload = ResourceRecordingSerializer.call(recording)

        refute payload.key?(:title)
        assert_equal(
          {
            "title" => "Docs Landing",
            "content" => "Hello world",
            "summary" => "Summary: Docs Landing"
          },
          payload.fetch(:attributes)
        )
      end

      def test_call_supports_app_level_enrichment_on_top_of_recordable_registration
        RecordingStudioApi.register_recordable_type_api(
          "Page",
          serializer: ->(recordable) { { label: recordable.title } }
        )

        RecordingStudioApi.register_recordable_type_api(
          "Page",
          serializer: ->(_recordable) { { source: "host_app" } }
        )

        recording = build_recording(
          recordable_type: "Page",
          recordable: RecordableStub.new(
            id: "page-2",
            title: "Changelog",
            attributes: {
              "id" => "page-2",
              "title" => "Changelog"
            }
          )
        )

        payload = ResourceRecordingSerializer.call(recording)

        refute payload.key?(:title)
        assert_equal(
          {
            "title" => "Changelog",
            "label" => "Changelog",
            "source" => "host_app"
          },
          payload.fetch(:attributes)
        )
      end

      def test_call_omits_attributes_when_merged_attributes_are_empty
        recording = build_recording(
          recordable_type: "Note",
          recordable: RecordableStub.new(
            id: "note-1",
            attributes: {}
          )
        )

        payload = ResourceRecordingSerializer.call(recording)

        refute payload.key?(:attributes)
      end

      def test_call_filters_actions_by_api_version_profile
        RecordingStudioApi.configuration.api_versions = %w[v1 v2]
        RecordingStudioApi.configuration.version("v1") { |api| api.use :publishable, "~> 1.0" }
        RecordingStudioApi.configuration.version("v2") { |api| api.use :publishable }
        RecordingStudioApi.register_capability_action(
          :publish,
          capability: :publishable,
          version: "2.0.0",
          handler: ->(_context) { :ok }
        )

        recording = build_recording(
          recordable_type: "Page",
          recordable: RecordableStub.new(
            id: "page-3",
            title: "Release Notes",
            attributes: {
              "id" => "page-3",
              "title" => "Release Notes"
            }
          )
        )

        RecordingStudio.stub(:capability_enabled?, ->(capability, **kwargs) { capability == :publishable && kwargs[:for] == "Page" }) do
          assert_equal [], ResourceRecordingSerializer.call(recording, version: "v1").fetch(:actions)
          assert_equal ["publish"], ResourceRecordingSerializer.call(recording, version: "v2").fetch(:actions)
        end
      end

      private

      def build_recording(recordable_type:, recordable:)
        Struct.new(:id, :recordable_type, :recordable, :root_recording_id, :parent_recording_id).new(
          "recording-1",
          recordable_type,
          recordable,
          "root-recording-1",
          nil
        )
      end
    end
  end
end
