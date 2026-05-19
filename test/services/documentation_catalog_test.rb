# frozen_string_literal: true

require "test_helper"

module RecordingStudioApi
  module Services
    class DocumentationCatalogTest < Minitest::Test
      ActionStub = Struct.new(:name, :http_verb, :capability, :scope, :openapi, keyword_init: true)

      def test_call_builds_shared_and_resource_endpoints
        catalog = with_catalog_stubs(
          recordable_types: %w[Workspace Page],
          actions_by_type: {
            "Workspace" => [ActionStub.new(name: "publish", http_verb: :post, capability: :publishable, scope: :member)],
            "Page" => []
          }
        ) do
          DocumentationCatalog.call
        end

        assert_equal "/recording_studio_api/oauth/token", catalog.fetch(:auth_endpoints).first.fetch(:path)
        assert_equal "/recording_studio_api/api/v1", catalog.fetch(:root_endpoints).first.fetch(:path)

        resources = catalog.fetch(:resources)
        assert_equal %w[pages workspaces], resources.map { |section| section.fetch(:resource) }

        workspace_section = resources.find { |section| section.fetch(:resource) == "workspaces" }
        endpoint_paths = workspace_section.fetch(:endpoints).map { |endpoint| endpoint.fetch(:path) }

        assert_includes endpoint_paths, "/recording_studio_api/api/v1/workspaces"
        assert_includes endpoint_paths, "/recording_studio_api/api/v1/workspaces/:id"
        assert_includes endpoint_paths, "/recording_studio_api/api/v1/workspaces/:id/actions"
        assert_includes endpoint_paths, "/recording_studio_api/api/v1/workspaces/:id/actions/publish"
      end

      def test_action_endpoints_include_capability_metadata
        catalog = with_catalog_stubs(
          recordable_types: ["Workspace"],
          actions_by_type: {
            "Workspace" => [
              ActionStub.new(
                name: "archive",
                http_verb: :patch,
                capability: :archivable,
                scope: :member,
                openapi: { summary: "Archive the record", tags: ["workspace-actions"] }
              )
            ]
          }
        ) do
          DocumentationCatalog.call
        end

        workspace_section = catalog.fetch(:resources).find { |section| section.fetch(:resource) == "workspaces" }
        action_endpoint = workspace_section.fetch(:endpoints).find do |endpoint|
          endpoint.fetch(:path) == "/recording_studio_api/api/v1/workspaces/:id/actions/archive"
        end

        assert_equal "PATCH", action_endpoint.fetch(:verb)
        assert_equal "archivable", action_endpoint.fetch(:action_name)
        assert_equal "member", action_endpoint.fetch(:scope)
        assert_equal "Archive the record", action_endpoint.fetch(:openapi).fetch(:summary)
        assert_equal ["workspace-actions"], action_endpoint.fetch(:openapi).fetch(:tags)
      end

      def test_default_action_openapi_groups_actions_under_resource_tag
        catalog = with_catalog_stubs(
          recordable_types: ["Folder"],
          actions_by_type: {
            "Folder" => [ActionStub.new(name: "move", http_verb: :post, capability: :movable, scope: :member)]
          }
        ) do
          DocumentationCatalog.call
        end

        folder_section = catalog.fetch(:resources).find { |section| section.fetch(:resource) == "folders" }
        move_endpoint = folder_section.fetch(:endpoints).find do |endpoint|
          endpoint.fetch(:path) == "/recording_studio_api/api/v1/folders/:id/actions/move"
        end

        assert_equal ["Folder"], move_endpoint.fetch(:openapi).fetch(:tags)
      end

      def test_default_resource_tags_are_human_readable_for_access
        catalog = with_catalog_stubs(
          recordable_types: ["RecordingStudio::Access"],
          actions_by_type: {
            "RecordingStudio::Access" => []
          }
        ) do
          DocumentationCatalog.call
        end

        access_section = catalog.fetch(:resources).find { |section| section.fetch(:resource) == "accesses" }
        index_endpoint = access_section.fetch(:endpoints).find do |endpoint|
          endpoint.fetch(:path) == "/recording_studio_api/api/v1/accesses"
        end

        assert_equal ["Access"], index_endpoint.fetch(:openapi).fetch(:tags)
      end

      def test_resource_responses_reference_recordable_specific_schema
        catalog = with_catalog_stubs(
          recordable_types: ["Page"],
          actions_by_type: {
            "Page" => []
          }
        ) do
          DocumentationCatalog.call
        end

        page_section = catalog.fetch(:resources).find { |section| section.fetch(:resource) == "pages" }
        index_endpoint = page_section.fetch(:endpoints).find do |endpoint|
          endpoint.fetch(:path) == "/recording_studio_api/api/v1/pages"
        end

        schema_ref = index_endpoint
          .fetch(:openapi)
          .fetch(:responses)
          .fetch("200")
          .fetch(:content)
          .fetch("application/json")
          .fetch(:schema)
          .fetch(:properties)
          .fetch(:data)
          .fetch(:items)
          .fetch("$ref")

        assert_equal "#/components/schemas/PageRecording", schema_ref
        assert index_endpoint
          .fetch(:openapi)
          .fetch(:responses)
          .fetch("200")
          .fetch(:content)
          .fetch("application/json")
          .fetch(:schema)
          .fetch(:properties)
          .key?(:type)
      end

      def test_recordable_openapi_endpoint_overrides_are_merged
        with_recordable_registration(
          "Page",
          openapi: {
            show: {
              summary: "Get page details"
            }
          }
        ) do
          catalog = with_catalog_stubs(
            recordable_types: ["Page"],
            actions_by_type: {
              "Page" => []
            }
          ) do
            DocumentationCatalog.call
          end

          page_section = catalog.fetch(:resources).find { |section| section.fetch(:resource) == "pages" }
          show_endpoint = page_section.fetch(:endpoints).find do |endpoint|
            endpoint.fetch(:path) == "/recording_studio_api/api/v1/pages/:id"
          end

          assert_equal "Get page details", show_endpoint.fetch(:openapi).fetch(:summary)
        end
      end

      private

      def with_catalog_stubs(recordable_types:, actions_by_type:)
        singleton = RecordingStudioApi.singleton_class
        original_recordable_types = RecordingStudioApi.method(:api_recordable_types)
        original_actions_for = RecordingStudioApi.method(:capability_actions_for)

        singleton.send(:define_method, :api_recordable_types) { recordable_types }
        singleton.send(:define_method, :capability_actions_for) do |recordable_type|
          actions_by_type.fetch(recordable_type, [])
        end

        yield
      ensure
        singleton.send(:define_method, :api_recordable_types, original_recordable_types)
        singleton.send(:define_method, :capability_actions_for, original_actions_for)
      end

      def with_recordable_registration(recordable_type, serializer: nil, openapi:)
        registry = RecordingStudioApi.configuration.recordable_registry
        existing = registry[recordable_type]

        registry.register(recordable_type, serializer: serializer, openapi: openapi)
        yield
      ensure
        if existing
          registry.register(recordable_type, serializer: existing.serializer, openapi: existing.openapi)
        else
          registry.instance_variable_get(:@registrations).delete(recordable_type)
        end
      end
    end
  end
end
