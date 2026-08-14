# frozen_string_literal: true

require "test_helper"

module RecordingStudioApi
  module Serializers
    class ResourceRecordingSerializerTest < Minitest::Test
      RecordableStub = Struct.new(:title, :name, keyword_init: true)
      RecordingStub = Struct.new(
        :id, :recordable_type, :recordable, :root_recording_id, :parent_recording_id, :created_at, :updated_at,
        keyword_init: true
      )

      class PreparedRelationshipContext
        attr_reader :access_grant, :api_key, :api_version, :params, :scoped_recordings, :selected_include_names

        def initialize(selected: [], values: {}, metadata: {}, access_grant: nil)
          @selected_include_names = selected.map(&:to_s)
          @values = values
          @metadata = metadata
          @access_grant = access_grant
          @api_key = :public
          @api_version = "v1"
          @params = {}
          @scoped_recordings = nil
        end

        def include?(name, definition)
          definition.include == true || (definition.include == :request && selected_include_names.include?(name.to_s))
        end

        def relationship_value(recording, name, _definition)
          @values.fetch([recording.id, name.to_s], @values.fetch(name.to_s, nil))
        end

        def relationship_metadata(recording, name)
          @metadata[[recording.id, name.to_s]] || @metadata[name.to_s]
        end
      end

      def test_call_returns_canonical_flat_payload
        payload = serialize(recording(type: "Page"), registration: registration("Page"))

        assert_equal "recording-1", payload.fetch(:id)
        assert_equal "Page", payload.fetch(:type)
        assert_nil payload.fetch(:parent_id)
        assert_equal "root-recording-1", payload.fetch(:root_id)
        assert_equal "2026-08-13T12:00:00Z", payload.fetch(:created_at)
        assert_equal "2026-08-13T13:00:00Z", payload.fetch(:updated_at)
        %i[attributes relationships data actions _meta].each { |key| refute payload.key?(key) }
      end

      def test_call_supports_legacy_and_context_aware_top_level_serializers
        resource = recording(type: "Page", title: "Guide")
        legacy = registration("Page", serializer: ->(recordable) { { label: recordable.title } }, output_keys: ["label"])
        aware = registration(
          "Page", serializer: ->(_recordable, context:) { { api_version: context.api_version } }, output_keys: ["api_version"]
        )

        assert_equal "Guide", serialize(resource, registration: legacy).fetch(:label)
        assert_equal "v1", serialize(resource, registration: aware).fetch(:api_version)
      end

      def test_call_rejects_undeclared_and_colliding_top_level_serializer_output
        resource = recording(type: "Page")
        cases = {
          undeclared: [{ unexpected: "value" }, registration("Page", serializer: ->(_) { { unexpected: "value" } }, output_keys: ["label"])],
          reserved: [{ id: "other" }, registration("Page", serializer: ->(_) { { id: "other" } }, output_keys: ["label"])],
          field: [{ field_label: "other" }, registration("Page", serializer: ->(_) { { field_label: "other" } }, output_keys: ["label"], fields: fields("field_label"))],
          relationship: [{ owner: "other" }, registration("Page", serializer: ->(_) { { owner: "other" } }, output_keys: ["label"], relationships: relationships("owner"))],
          meta: [{ _meta: {} }, registration("Page", serializer: ->(_) { { _meta: {} } }, output_keys: ["label"])]
        }

        cases.each_value do |_output, configured_registration|
          assert_raises(ConfigurationError) { serialize(resource, registration: configured_registration) }
        end
      end

      def test_call_resolves_only_included_fields_and_keeps_json_safe_values
        resource = recording(type: "Page")
        configured_registration = registration(
          "Page",
          fields: {
            "always" => { resolver: ->(_context) { "visible" }, include: true },
            "requested" => { resolver: ->(_context) { [nil, { "published" => true }] }, include: :request },
            "hidden" => { resolver: ->(_context) { raise "must not resolve" }, include: false }
          }
        )
        context = PreparedRelationshipContext.new(selected: ["requested"])

        payload = serialize(resource, registration: configured_registration, context: context)

        assert_equal "visible", payload.fetch(:always)
        assert_equal [nil, { "published" => true }], payload.fetch(:requested)
        refute payload.key?(:hidden)
      end

      def test_call_authorizes_fields_and_fails_closed
        resource = recording(type: "Page")
        permitted = registration(
          "Page", fields: {
            "secret" => { resolver: ->(_context) { "allowed" }, include: true, authorize: ->(context) { context.access_grant == :grant } }
          }
        )

        assert_equal "allowed", serialize(resource, registration: permitted, context: PreparedRelationshipContext.new(access_grant: :grant)).fetch(:secret)
        assert_raises(AuthorizationError) { serialize(resource, registration: permitted, context: PreparedRelationshipContext.new(access_grant: :denied)) }
        assert_raises(AuthorizationError) { serialize(resource, registration: permitted, context: PreparedRelationshipContext.new) }
      end

      def test_call_rejects_non_json_safe_field_values
        configured_registration = registration(
          "Page", fields: { "owner" => { resolver: ->(_context) { Object.new }, include: true } }
        )

        assert_raises(ConfigurationError) { serialize(recording(type: "Page"), registration: configured_registration, context: PreparedRelationshipContext.new) }
      end

      def test_call_serializes_singular_and_many_relationships_with_metadata
        parent = recording(type: "Page", id: "parent-1")
        child = recording(type: "Folder", id: "child-1", title: "Child")
        configured_registration = registration(
          "Page",
          relationships: {
            "owner" => relationship(serializer: ->(recordable) { { label: recordable.title } }),
            "children" => relationship(many: true, serializer: ->(recordable) { { label: recordable.title } })
          }
        )
        context = PreparedRelationshipContext.new(
          selected: %w[owner children], values: { "owner" => child, "children" => [child] }, metadata: { "children" => { "count" => 1 } }
        )

        payload = serialize(parent, registration: configured_registration, context: context)

        assert_equal "child-1", payload.fetch("owner").fetch(:id)
        assert_equal "Child", payload.fetch("owner").fetch(:label)
        assert_equal(["child-1"], payload.fetch("children").map { |entry| entry.fetch(:id) })
        assert_equal({ "count" => 1 }, payload.fetch(:_meta).fetch("children"))

        null_context = PreparedRelationshipContext.new(selected: ["owner"], values: { "owner" => nil })
        assert_nil serialize(parent, registration: configured_registration, context: null_context).fetch("owner")
      end

      def test_relationship_serializer_is_used_instead_of_child_registration_and_does_not_expand_nested_relationships
        parent = recording(type: "Page", id: "parent-1")
        child = recording(type: "Folder", id: "child-1", title: "Child")
        parent_registration = registration(
          "Page", relationships: { "owner" => relationship(serializer: ->(recordable) { { relationship_label: recordable.title } }, output_keys: ["relationship_label"]) }
        )
        child_registration = registration(
          "Folder", serializer: ->(_recordable) { { child_label: "wrong serializer" } }, output_keys: ["child_label"],
                    relationships: { "nested" => relationship }
        )
        context = PreparedRelationshipContext.new(selected: ["owner"], values: { "owner" => child })

        payload = with_registrations("Page" => parent_registration, "Folder" => child_registration) do
          ResourceRecordingSerializer.call(parent, context: context)
        end

        assert_equal "Child", payload.fetch("owner").fetch(:relationship_label)
        refute payload.fetch("owner").key?(:child_label)
        refute payload.fetch("owner").key?("nested")
      end

      def test_call_rejects_invalid_relationship_serializer_output_and_non_recording_targets
        parent = recording(type: "Page", id: "parent-1")
        child = recording(type: "Folder", id: "child-1")
        invalid_outputs = [
          ->(_recordable) { { unexpected: "value" } },
          ->(_recordable) { { id: "other" } }
        ]

        invalid_outputs.each do |serializer|
          configured_registration = registration("Page", relationships: { "owner" => relationship(serializer: serializer) })
          context = PreparedRelationshipContext.new(selected: ["owner"], values: { "owner" => child })
          assert_raises(ConfigurationError) { serialize(parent, registration: configured_registration, context: context) }
        end

        configured_registration = registration("Page", relationships: { "owner" => relationship })
        context = PreparedRelationshipContext.new(selected: ["owner"], values: { "owner" => RecordableStub.new(title: "not a recording") })
        assert_raises(ConfigurationError) { serialize(parent, registration: configured_registration, context: context) }
      end

      private

      def recording(type:, id: "recording-1", title: "Title")
        RecordingStub.new(
          id: id, recordable_type: type, recordable: RecordableStub.new(title: title), root_recording_id: "root-recording-1",
          parent_recording_id: nil, created_at: Time.utc(2026, 8, 13, 12), updated_at: Time.utc(2026, 8, 13, 13)
        )
      end

      def fields(name)
        { name => { resolver: ->(_context) { "field" }, include: true } }
      end

      def relationship(many: false, serializer: ->(recordable) { { label: recordable.title } }, output_keys: ["label"])
        options = { source: :custom, many: many, include: :request, resolver: ->(_context) {}, serializer: serializer, output_keys: output_keys }
        options[:limit] = 10 if many
        options
      end

      def relationships(name)
        { name => relationship }
      end

      def registration(type, serializer: nil, output_keys: [], fields: {}, relationships: {})
        RecordableRegistration.new(recordable_type: type, serializer: serializer, output_keys: output_keys, fields: fields, relationships: relationships)
      end

      def serialize(resource, registration:, context: nil, version: "v1")
        with_registrations(resource.recordable_type => registration) do
          ResourceRecordingSerializer.call(resource, context: context, version: version)
        end
      end

      def with_registrations(registrations, &)
        RecordingStudioApi.stub(:recordable_registration_for, ->(type, **) { registrations.fetch(type.to_s) }, &)
      end
    end
  end
end
