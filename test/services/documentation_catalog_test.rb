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
        assert_equal "/recording_studio_api/oauth/revoke", catalog.fetch(:auth_endpoints).second.fetch(:path)
        assert_equal 2, catalog.fetch(:auth_endpoints).length
        assert_equal "/recording_studio_api/api/v1", catalog.fetch(:root_endpoints).first.fetch(:path)

        resources = catalog.fetch(:resources)
        assert_equal %w[pages workspaces], resources.map { |section| section.fetch(:resource) }

        workspace_section = resources.find { |section| section.fetch(:resource) == "workspaces" }
        endpoint_paths = workspace_section.fetch(:endpoints).map { |endpoint| endpoint.fetch(:path) }
        destroy_endpoint = workspace_section.fetch(:endpoints).find do |endpoint|
          endpoint.fetch(:path) == "/recording_studio_api/api/v1/workspaces/:id" && endpoint.fetch(:verb) == "DELETE"
        end

        assert_includes endpoint_paths, "/recording_studio_api/api/v1/workspaces"
        assert_includes endpoint_paths, "/recording_studio_api/api/v1/workspaces/:id"
        assert_includes endpoint_paths, "/recording_studio_api/api/v1/workspaces/:id/actions/publish"
        assert_equal "resources#destroy", destroy_endpoint.fetch(:action)
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
        assert_equal "Move", move_endpoint.fetch(:summary)
        action_response_schema = move_endpoint
          .fetch(:openapi)
          .fetch(:responses)
          .fetch("200")
          .fetch(:content)
          .fetch("application/json")
          .fetch(:schema)
        assert_equal "object", action_response_schema.fetch(:type)
        assert action_response_schema.fetch(:properties).key?(:id)
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

        access_section = catalog.fetch(:resources).find { |section| section.fetch(:resource) == "access" }
        index_endpoint = access_section.fetch(:endpoints).find do |endpoint|
          endpoint.fetch(:path) == "/recording_studio_api/api/v1/access"
        end

        assert_equal "List Access", index_endpoint.fetch(:summary)
        assert_equal ["Access"], index_endpoint.fetch(:openapi).fetch(:tags)
      end

      def test_resource_responses_reference_shared_recording_schema
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

        item_schema = index_endpoint
          .fetch(:openapi)
          .fetch(:responses)
          .fetch("200")
          .fetch(:content)
          .fetch("application/json")
          .fetch(:schema)
          .fetch(:properties)
          .fetch(:records)
          .fetch(:items)

        assert_equal "object", item_schema.fetch(:type)
        assert item_schema.fetch(:properties).key?(:id)
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
            },
            preserve_recordable_registrations: true
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

      def test_named_relationship_adds_generic_relationship_endpoints_to_documentation
        with_recordable_registration(
          "Workspace",
          relationships: {
            folders: { source: :children, child_type: "Folder", many: true, serializer: ->(*) {},
                       output_keys: %i[name], limit: 20, endpoints: %i[index show create] }
          }
        ) do
          catalog = with_catalog_stubs(
            recordable_types: ["Workspace"],
            actions_by_type: { "Workspace" => [] },
            preserve_recordable_registrations: true
          ) { DocumentationCatalog.call }

          endpoints = catalog.fetch(:resources).first.fetch(:endpoints)
          assert_includes endpoints.map { |endpoint| [endpoint.fetch(:verb), endpoint.fetch(:path)] },
                          ["GET", "/recording_studio_api/api/v1/workspaces/:id/folders"]
          assert_includes endpoints.map { |endpoint| [endpoint.fetch(:verb), endpoint.fetch(:path)] },
                          ["GET", "/recording_studio_api/api/v1/workspaces/:id/folders/:relationship_id"]
          assert_includes endpoints.map { |endpoint| [endpoint.fetch(:verb), endpoint.fetch(:path)] },
                          ["POST", "/recording_studio_api/api/v1/workspaces/:id/folders"]
        end
      end

      def test_named_relationship_responses_describe_declared_child_types
        with_recordable_registration(
          "Workspace",
          relationships: {
            folders: { source: :children, child_type: "Folder", many: true, serializer: ->(*) {},
                       output_keys: %i[name], limit: 20, endpoints: %i[index show create] }
          }
        ) do
          with_recordable_registration(
            "Folder",
            openapi: {
              details_schema: {
                properties: {
                  name: { type: "string" }
                }
              }
            }
          ) do
            catalog = with_catalog_stubs(
              recordable_types: %w[Workspace Folder],
              actions_by_type: { "Workspace" => [], "Folder" => [] },
              preserve_recordable_registrations: true
            ) { DocumentationCatalog.call }

            endpoint = catalog.fetch(:resources).find { |section| section.fetch(:resource) == "workspaces" }
              .fetch(:endpoints).find { |entry| entry.fetch(:verb) == "POST" && entry.fetch(:path).end_with?("/folders") }
            properties = endpoint.fetch(:openapi).fetch(:responses).fetch("201")
              .fetch(:content).fetch("application/json").fetch(:schema)
              .fetch(:properties)

            assert_equal "string", properties.fetch(:name).fetch(:type)
          end
        end

        def test_custom_relationship_schema_supports_singular_or_collection_values
          with_recordable_registration(
            "Workspace",
            relationships: {
              owner: {
                source: :custom,
                many: false,
                include: true,
                resolver: ->(_workspace) {},
                serializer: ->(*) {},
                output_keys: %i[name]
              }
            }
          ) do
            catalog = with_catalog_stubs(
              recordable_types: ["Workspace"],
              actions_by_type: { "Workspace" => [] },
              preserve_recordable_registrations: true
            ) { DocumentationCatalog.call }

            schema = catalog.fetch(:resources).first.fetch(:endpoints)
              .find { |endpoint| endpoint.fetch(:verb) == "GET" && endpoint.fetch(:path).end_with?("/workspaces/:id") }
              .fetch(:openapi).fetch(:responses).fetch("200").fetch(:content).fetch("application/json").fetch(:schema)
            assert schema.fetch(:properties).fetch(:owner).key?(:oneOf)
          end
        end

        def test_relationship_show_endpoint_is_omitted_when_no_child_type_supports_show
          with_recordable_registration(
            "Workspace",
            relationships: {
              folders: { source: :children, child_type: "Folder", many: true, serializer: ->(*) {},
                         output_keys: %i[name], limit: 20, endpoints: %i[index show] }
            }
          ) do
            with_recordable_registration("Folder", operations: %i[index]) do
              catalog = with_catalog_stubs(
                recordable_types: %w[Workspace Folder],
                actions_by_type: { "Workspace" => [], "Folder" => [] },
                preserve_recordable_registrations: true
              ) { DocumentationCatalog.call }

              paths = catalog.fetch(:resources).find { |section| section.fetch(:resource) == "workspaces" }
                .fetch(:endpoints).map { |endpoint| endpoint.fetch(:path) }
              refute_includes paths, "/recording_studio_api/api/v1/workspaces/:id/folders/:relationship_id"
            end
          end
        end
      end

      def test_action_request_body_uses_input_contract_schema
        input_contract = Struct.new(:as_json).new(
          {
            fields: {
              title: { type: :string, required: true, description: "Title" },
              published: { type: :boolean, required: false },
              score: { type: :float, required: false },
              tags: { type: :array, required: false },
              mode: { type: :string, required: false, enum: %w[draft final] }
            }
          }
        )

        action = ActionStub.new(
          name: "publish",
          http_verb: :post,
          capability: :publishable,
          scope: :member,
          openapi: {}
        )
        action.define_singleton_method(:input_contract) { input_contract }

        catalog = with_catalog_stubs(
          recordable_types: ["Page"],
          actions_by_type: {
            "Page" => [action]
          }
        ) do
          DocumentationCatalog.call
        end

        page_section = catalog.fetch(:resources).find { |section| section.fetch(:resource) == "pages" }
        endpoint = page_section.fetch(:endpoints).find { |entry| entry.fetch(:path).end_with?("/actions/publish") }
        schema = endpoint.fetch(:openapi).fetch(:request_body).fetch(:content).fetch("application/json").fetch(:schema)

        assert_equal "object", schema.fetch(:type)
        assert_equal ["title"], schema.fetch(:required)
        assert_equal "string", schema.fetch(:properties).fetch("title").fetch(:type)
        assert_equal "boolean", schema.fetch(:properties).fetch("published").fetch(:type)
        assert_equal "number", schema.fetch(:properties).fetch("score").fetch(:type)
        assert_equal "array", schema.fetch(:properties).fetch("tags").fetch(:type)
        assert_equal %w[draft final], schema.fetch(:properties).fetch("mode").fetch(:enum)
      end

      def test_nested_endpoints_require_many_children_endpoints_and_child_operations
        relationships = {
          folders: { source: :children, child_type: "Folder", many: true, serializer: ->(*) {},
                     output_keys: %i[name], limit: 20, endpoints: %i[index create] },
          owner: { source: :custom, many: false, include: true, resolver: ->(*) {},
                   serializer: ->(*) {}, output_keys: %i[name] }
        }

        with_recordable_registration("Workspace", relationships: relationships) do
          with_recordable_registration("Folder", operations: %i[index]) do
            catalog = with_catalog_stubs(
              recordable_types: %w[Workspace Folder],
              actions_by_type: { "Workspace" => [], "Folder" => [] },
              preserve_recordable_registrations: true
            ) { DocumentationCatalog.call }

            paths = catalog.fetch(:resources).find { |section| section.fetch(:resource) == "workspaces" }
              .fetch(:endpoints).map { |endpoint| [endpoint.fetch(:verb), endpoint.fetch(:path)] }
            assert_includes paths, ["GET", "/recording_studio_api/api/v1/workspaces/:id/folders"]
            refute_includes paths, ["POST", "/recording_studio_api/api/v1/workspaces/:id/folders"]
            refute(paths.any? { |_verb, path| path.include?("/owner") })
          end
        end
      end

      def test_nested_create_request_body_contains_flat_writable_properties
        relationships = {
          folders: { source: :children, child_type: "Folder", many: true, serializer: ->(*) {},
                     output_keys: %i[name], limit: 20, endpoints: %i[create] }
        }

        with_recordable_registration("Workspace", relationships: relationships) do
          with_recordable_registration(
            "Folder",
            operations: %i[create],
            writable_attributes: %i[name],
            openapi: { details_schema: { properties: { name: { type: "string" } } } }
          ) do
            catalog = with_catalog_stubs(
              recordable_types: %w[Workspace Folder],
              actions_by_type: { "Workspace" => [], "Folder" => [] },
              preserve_recordable_registrations: true
            ) { DocumentationCatalog.call }
            endpoint = catalog.fetch(:resources).find { |section| section.fetch(:resource) == "workspaces" }
              .fetch(:endpoints).find { |entry| entry.fetch(:verb) == "POST" && entry.fetch(:path).end_with?("/folders") }
            schema = endpoint.fetch(:openapi).fetch(:request_body).fetch(:content).fetch("application/json").fetch(:schema)

            assert_equal [:name], schema.fetch(:properties).keys
            assert_equal false, schema.fetch(:additionalProperties)
            refute schema.fetch(:properties).key?(:attributes)
            refute schema.key?(:required)
          end
        end
      end

      def test_nested_show_endpoint_is_documented_without_index
        relationships = {
          folders: { source: :children, child_type: "Folder", many: true, serializer: ->(*) {},
                     output_keys: %i[name], limit: 20, endpoints: %i[show] }
        }

        with_recordable_registration("Workspace", relationships: relationships) do
          with_recordable_registration("Folder", operations: %i[show]) do
            catalog = with_catalog_stubs(
              recordable_types: %w[Workspace Folder],
              actions_by_type: { "Workspace" => [], "Folder" => [] },
              preserve_recordable_registrations: true
            ) { DocumentationCatalog.call }
            paths = catalog.fetch(:resources).find { |section| section.fetch(:resource) == "workspaces" }
              .fetch(:endpoints).map { |endpoint| [endpoint.fetch(:verb), endpoint.fetch(:path)] }

            assert_includes paths, ["GET", "/recording_studio_api/api/v1/workspaces/:id/folders/:relationship_id"]
            refute_includes paths, ["GET", "/recording_studio_api/api/v1/workspaces/:id/folders"]
          end
        end
      end

      def test_catalog_uses_configured_default_api_version_in_paths
        original_version = RecordingStudioApi.configuration.default_api_version

        RecordingStudioApi.configuration.default_api_version = "v2"
        catalog = with_catalog_stubs(
          recordable_types: ["Page"],
          actions_by_type: {
            "Page" => []
          }
        ) do
          DocumentationCatalog.call
        end

        assert_equal "/recording_studio_api/api/v2", catalog.fetch(:root_endpoints).first.fetch(:path)

        page_section = catalog.fetch(:resources).find { |section| section.fetch(:resource) == "pages" }
        endpoint_paths = page_section.fetch(:endpoints).map { |endpoint| endpoint.fetch(:path) }
        assert_includes endpoint_paths, "/recording_studio_api/api/v2/pages"
      ensure
        RecordingStudioApi.configuration.default_api_version = original_version
      end

      def test_catalog_accepts_explicit_version_argument
        original_versions = RecordingStudioApi.configuration.api_versions
        original_version = RecordingStudioApi.configuration.default_api_version

        RecordingStudioApi.configuration.api_versions = %w[v1 v2]
        RecordingStudioApi.configuration.default_api_version = "v1"

        catalog = with_catalog_stubs(
          recordable_types: ["Page"],
          actions_by_type: {
            "Page" => []
          }
        ) do
          DocumentationCatalog.call(version: "v2")
        end

        assert_equal "/recording_studio_api/api/v2", catalog.fetch(:root_endpoints).first.fetch(:path)
      ensure
        RecordingStudioApi.configuration.api_versions = original_versions
        RecordingStudioApi.configuration.default_api_version = original_version
      end

      def test_catalog_uses_explicit_mount_context
        original_versions = RecordingStudioApi.configuration.api_versions
        original_version = RecordingStudioApi.configuration.default_api_version
        RecordingStudioApi.configuration.api_versions = %w[v1 v2]

        catalog = with_catalog_stubs(
          recordable_types: ["Page"],
          actions_by_type: { "Page" => [] }
        ) do
          DocumentationCatalog.call(
            version: "v2",
            mount_path: "/platform/recording-api",
            api_mount_path: "/public-api"
          )
        end

        assert_equal "/platform/recording-api/oauth/token", catalog.fetch(:auth_endpoints).first.fetch(:path)
        assert_equal "/platform/recording-api/oauth/revoke", catalog.fetch(:auth_endpoints).second.fetch(:path)
        assert_equal "/platform/recording-api/public-api/v2", catalog.fetch(:root_endpoints).first.fetch(:path)
      ensure
        RecordingStudioApi.configuration.api_versions = original_versions
        RecordingStudioApi.configuration.default_api_version = original_version
      end

      def test_catalog_rejects_unsafe_mount_context
        error = assert_raises(ArgumentError) do
          DocumentationCatalog.call(mount_path: "/platform/../private")
        end

        assert_equal "mount paths must be safe absolute paths", error.message
      end

      def test_resource_write_request_body_uses_closed_flat_schema_when_unregistered
        catalog = with_catalog_stubs(
          recordable_types: ["Workspace"],
          root_recordable_types: ["Workspace"],
          actions_by_type: {
            "Workspace" => []
          }
        ) do
          DocumentationCatalog.call
        end

        section = catalog.fetch(:resources).find { |resource| resource.fetch(:resource) == "workspaces" }
        create_endpoint = section.fetch(:endpoints).find { |entry| entry.fetch(:verb) == "POST" && entry.fetch(:action) == "resources#create" }
        schema = create_endpoint.fetch(:openapi).fetch(:request_body).fetch(:content).fetch("application/json").fetch(:schema)

        assert_equal [:parent_id], schema.fetch(:properties).keys
        assert_equal false, schema.fetch(:additionalProperties)
        assert_equal [], schema.fetch(:required)
        refute schema.fetch(:properties).key?(:attributes)
        assert_equal true, schema.fetch(:properties).fetch(:parent_id).fetch(:nullable)
      end

      def test_resource_write_request_body_requires_parent_id_for_non_root_recordables
        catalog = with_catalog_stubs(
          recordable_types: ["Page"],
          root_recordable_types: [],
          actions_by_type: {
            "Page" => []
          }
        ) do
          DocumentationCatalog.call
        end

        section = catalog.fetch(:resources).find { |resource| resource.fetch(:resource) == "pages" }
        create_endpoint = section.fetch(:endpoints).find { |entry| entry.fetch(:verb) == "POST" && entry.fetch(:action) == "resources#create" }
        schema = create_endpoint.fetch(:openapi).fetch(:request_body).fetch(:content).fetch("application/json").fetch(:schema)

        assert_equal ["parent_id"], schema.fetch(:required)
        refute schema.fetch(:properties).key?(:attributes)
        refute schema.fetch(:properties).fetch(:parent_id).key?(:nullable)
      end

      def test_resource_update_request_body_documents_flat_writable_fields_without_parent_id
        with_recordable_registration(
          "Workspace",
          writable_attributes: %i[name],
          openapi: { details_schema: { properties: { name: { type: "string" } } } }
        ) do
          catalog = with_catalog_stubs(
            recordable_types: ["Workspace"],
            root_recordable_types: ["Workspace"],
            actions_by_type: { "Workspace" => [] },
            preserve_recordable_registrations: true
          ) { DocumentationCatalog.call }

          section = catalog.fetch(:resources).find { |resource| resource.fetch(:resource) == "workspaces" }
          update_endpoint = section.fetch(:endpoints).find { |entry| entry.fetch(:verb) == "PATCH" }
          schema = update_endpoint.fetch(:openapi).fetch(:request_body).fetch(:content).fetch("application/json").fetch(:schema)

          assert_equal [:name], schema.fetch(:properties).keys
          refute schema.fetch(:properties).key?(:attributes)
          refute schema.fetch(:properties).key?(:parent_id)
          assert_equal false, schema.fetch(:additionalProperties)
        end
      end

      def test_catalog_selects_action_contract_by_api_version_profile
        original_configuration = RecordingStudioApi.configuration
        api_singleton = RecordingStudioApi.singleton_class
        original_recordable_types = RecordingStudioApi.method(:api_recordable_types)

        RecordingStudioApi.instance_variable_set(:@configuration, RecordingStudioApi::Configuration.new)
        RecordingStudioApi.configuration.api_versions = %w[v1 v2]
        RecordingStudioApi.configuration.version("v1") { |api| api.use :publishable, "~> 1.0" }
        RecordingStudioApi.configuration.version("v2") { |api| api.use :publishable }

        RecordingStudioApi.register_capability_action(
          :publish,
          capability: :publishable,
          version: "1.4.0",
          http_verb: :post,
          handler: ->(_context) { :legacy },
          openapi: { summary: "Publish legacy" }
        )
        RecordingStudioApi.register_capability_action(
          :publish,
          capability: :publishable,
          version: "2.0.0",
          http_verb: :post,
          handler: ->(_context) { :current },
          openapi: { summary: "Publish current" }
        )
        RecordingStudioApi.register_recordable_type_api("Page", capability_actions: %i[publish])

        api_singleton.send(:define_method, :api_recordable_types) { ["Page"] }

        RecordingStudio.stub(:capability_enabled?, ->(capability, **kwargs) { capability == :publishable && kwargs[:for] == "Page" }) do
          v1_catalog = DocumentationCatalog.call(version: "v1")
          v2_catalog = DocumentationCatalog.call(version: "v2")

          assert_equal "Publish legacy", action_endpoint_summary(v1_catalog, "pages", "publish")
          assert_equal "Publish current", action_endpoint_summary(v2_catalog, "pages", "publish")
        end
      ensure
        api_singleton.send(:define_method, :api_recordable_types, original_recordable_types) if api_singleton && original_recordable_types
        RecordingStudioApi.instance_variable_set(:@configuration, original_configuration) if original_configuration
      end

      private

      def action_endpoint_summary(catalog, resource_name, action_name)
        section = catalog.fetch(:resources).find { |resource| resource.fetch(:resource) == resource_name }
        endpoint = section.fetch(:endpoints).find { |entry| entry.fetch(:path).end_with?("/actions/#{action_name}") }

        endpoint.fetch(:summary)
      end

      def with_catalog_stubs(recordable_types:, actions_by_type:, root_recordable_types: [], preserve_recordable_registrations: false)
        api_singleton = RecordingStudioApi.singleton_class
        declarations_singleton = RecordingStudio::RecordableDeclarations.singleton_class
        original_recordable_types = RecordingStudioApi.method(:api_recordable_types)
        original_actions_for = RecordingStudioApi.method(:capability_actions_for)
        original_root_allowed = RecordingStudio::RecordableDeclarations.method(:root_allowed?)
        original_registration_for = RecordingStudioApi.method(:recordable_registration_for)

        api_singleton.send(:define_method, :api_recordable_types) { recordable_types }
        api_singleton.send(:define_method, :capability_actions_for) do |recordable_type, **|
          actions_by_type.fetch(recordable_type, [])
        end
        api_singleton.send(:define_method, :recordable_registration_for) do |recordable_type, **|
          original_registration_for.call(recordable_type) if preserve_recordable_registrations
        end
        declarations_singleton.send(:define_method, :root_allowed?) do |recordable_type|
          root_recordable_types.include?(recordable_type.to_s)
        end

        yield
      ensure
        api_singleton.send(:define_method, :api_recordable_types, original_recordable_types)
        api_singleton.send(:define_method, :capability_actions_for, original_actions_for)
        api_singleton.send(:define_method, :recordable_registration_for, original_registration_for)
        declarations_singleton.send(:define_method, :root_allowed?, original_root_allowed)
      end

      def with_recordable_registration(
        recordable_type,
        serializer: nil,
        output_keys: nil,
        fields: nil,
        openapi: {},
        relationships: nil,
        immutable_relationships: nil,
        operations: nil,
        writable_attributes: nil
      )
        registry = RecordingStudioApi.configuration.recordable_registry
        registrations = registry.instance_variable_get(:@registrations)
        existing = registrations[recordable_type]
        # Drop any prior registration so relationship/operation overrides can be applied cleanly.
        registrations.delete(recordable_type)

        registry.register(
          recordable_type,
          serializer: serializer,
          output_keys: output_keys,
          fields: fields,
          openapi: openapi,
          relationships: relationships,
          immutable_relationships: immutable_relationships,
          operations: operations,
          writable_attributes: writable_attributes
        )
        yield
      ensure
        existing ? registrations[recordable_type] = existing : registrations.delete(recordable_type)
      end
    end
  end
end
