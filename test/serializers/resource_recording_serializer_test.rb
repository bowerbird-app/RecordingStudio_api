# frozen_string_literal: true

require "test_helper"

module RecordingStudioApi
  module Serializers
    class ResourceRecordingSerializerTest < Minitest::Test
      RecordableStub = Struct.new(:id, :name, :title, :attributes, keyword_init: true)
      RelationshipContextStub = Struct.new(:included, keyword_init: true) do
        def include?(_name, _definition)
          included
        end

        def relationship_value(_recording, _name, definition)
          definition.fetch(:resolver).call
        end
      end

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

      def test_call_returns_the_canonical_flat_payload_when_no_fields_are_registered
        recording = build_recording(
          recordable_type: "Folder",
          recordable: RecordableStub.new(
            id: "folder-1",
            name: "Marketing",
            attributes: {
              "id" => "folder-1",
              "name" => "Marketing",
              "password_digest" => "secret-digest",
              "created_at" => Time.now,
              "updated_at" => Time.now
            }
          )
        )

        payload = ResourceRecordingSerializer.call(recording)

        refute payload.key?(:title)
        refute payload.key?(:attributes)
        refute payload.key?(:relationships)
        assert payload.key?(:created_at)
        assert payload.key?(:updated_at)
      end

      def test_call_uses_registered_output_keys_and_fields_at_the_top_level
        RecordingStudioApi.register_recordable_type_api(
          "Page",
          output_keys: %i[summary],
          fields: { summary: ->(recordable) { "Summary: #{recordable.title}" } }
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
        assert_equal "Summary: Docs Landing", payload.fetch(:summary)
        refute payload.key?(:attributes)
      end

      def test_call_merges_fields_from_multiple_registrations
        RecordingStudioApi.register_recordable_type_api(
          "Page",
          output_keys: %i[label],
          fields: { label: ->(recordable) { recordable.title } }
        )

        RecordingStudioApi.register_recordable_type_api(
          "Page",
          output_keys: %i[source],
          fields: { source: ->(_recordable) { "host_app" } }
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
        assert_equal "Changelog", payload.fetch(:label)
        assert_equal "host_app", payload.fetch(:source)
      end

      def test_call_omits_unregistered_fields
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

      def test_call_does_not_allow_output_fields_to_override_canonical_keys
        RecordingStudioApi.register_recordable_type_api(
          "Page",
          output_keys: %i[external_key id],
          fields: {
            external_key: ->(recordable, context: nil) { "#{recordable.id}:#{context}" },
            id: ->(_recordable) { "must-not-overwrite" }
          }
        )
        recording = build_recording(
          recordable_type: "Page",
          recordable: RecordableStub.new(id: "page-4", title: "Flat", attributes: {})
        )

        payload = ResourceRecordingSerializer.call(recording, context: "request-context")

        assert_equal "page-4:request-context", payload.fetch(:external_key)
        assert_equal "recording-1", payload.fetch(:id)
      end

      def test_call_does_not_invoke_an_unreadable_always_included_relationship_resolver
        RecordingStudioApi.register_recordable_type_api(
          "Page",
          relationships: {
            owner: {
              source: :custom,
              include: true,
              read: false,
              resolver: ->(_recordable) { raise "owner resolver invoked" },
              output_keys: %i[name],
              fields: { name: :name }
            }
          }
        )
        recording = build_recording(
          recordable_type: "Page",
          recordable: RecordableStub.new(id: "page-5", attributes: {})
        )

        payload = ResourceRecordingSerializer.call(
          recording,
          context: RelationshipContextStub.new(included: true)
        )

        refute payload.key?(:owner)
      end

      def test_call_does_not_invoke_an_unreadable_request_included_relationship_resolver
        RecordingStudioApi.register_recordable_type_api(
          "Page",
          relationships: {
            owner: {
              source: :custom,
              include: :request,
              read: false,
              resolver: ->(_recordable) { raise "owner resolver invoked" },
              output_keys: %i[name],
              fields: { name: :name }
            }
          }
        )
        recording = build_recording(
          recordable_type: "Page",
          recordable: RecordableStub.new(id: "page-6", attributes: {})
        )

        payload = ResourceRecordingSerializer.call(
          recording,
          context: RelationshipContextStub.new(included: true)
        )

        refute payload.key?(:owner)
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
        RecordingStudioApi.register_recordable_type_api("Page", capability_actions: %i[publish])

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
