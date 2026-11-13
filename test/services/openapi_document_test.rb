# frozen_string_literal: true

require "test_helper"

module RecordingStudioApi
  module Services
    class OpenapiDocumentTest < Minitest::Test
      def test_named_api_document_uses_its_own_resources_metadata_and_paths
        original_configuration = RecordingStudioApi.configuration
        configuration = RecordingStudioApi::Configuration.new
        RecordingStudioApi.instance_variable_set(:@configuration, configuration)
        operations = configuration.api(:operations)
        operations.openapi_title = "Operations API"
        operations.openapi_description = "Operational diagnostics"
        operations.recordable_registry.register("AdminRoot")

        document = OpenapiDocument.call(api: :operations)

        assert_equal "Operations API", document.dig(:info, :title)
        assert_equal "Operational diagnostics", document.dig(:info, :description)
        assert_includes document.fetch(:paths).keys, "/recording_studio_api/apis/operations/v1/admin_roots"
        refute(document.fetch(:paths).keys.any? { |path| path.include?("workspaces") })
      ensure
        RecordingStudioApi.instance_variable_set(:@configuration, original_configuration)
      end

      def test_call_builds_openapi_document_with_paths
        document = with_isolated_configuration { OpenapiDocument.call }
        expected_title = Rails.application.class.module_parent_name.presence || "RecordingStudioApi"

        assert_equal "3.0.3", document.fetch(:openapi)
        assert_equal expected_title, document.fetch(:info).fetch(:title)
        assert_equal "API endpoints for accessing and managing Recording Studio resources.", document.fetch(:info).fetch(:description)
        assert_includes document.fetch(:tags), {
          name: "Authentication",
          description: "Authenticate your application with its client credentials to receive a bearer token for API requests."
        }
        assert_includes document.fetch(:tags), {
          name: "resources",
          description: "Discover the resource collections available through this API."
        }
        assert document.fetch(:paths).key?("/recording_studio_api/oauth/token")
        assert document.fetch(:paths).key?("/recording_studio_api/oauth/revoke")
        assert document.fetch(:paths).key?("/recording_studio_api/api/v1")
        assert document.fetch(:components).fetch(:schemas).key?(:OAuthTokenResponse)
        assert document.fetch(:components).fetch(:schemas).key?(:OAuthError)
        assert document.fetch(:components).fetch(:responses).key?(:Unauthorized)
        assert document.fetch(:components).fetch(:securitySchemes).key?(:oauthHttpBasic)
      end

      def test_call_uses_configured_openapi_title_when_present
        original_configuration_defined = RecordingStudioApi.instance_variable_defined?(:@configuration)
        original_configuration = RecordingStudioApi.instance_variable_get(:@configuration)
        configured = RecordingStudioApi::Configuration.new
        configured.openapi_title = "Custom API Title"
        RecordingStudioApi.instance_variable_set(:@configuration, configured)

        document = OpenapiDocument.call

        assert_equal "Custom API Title", document.fetch(:info).fetch(:title)
      ensure
        if original_configuration_defined
          RecordingStudioApi.instance_variable_set(:@configuration, original_configuration)
        else
          RecordingStudioApi.remove_instance_variable(:@configuration) if RecordingStudioApi.instance_variable_defined?(:@configuration)
        end
      end

      def test_call_uses_configured_openapi_description_when_present
        original_configuration_defined = RecordingStudioApi.instance_variable_defined?(:@configuration)
        original_configuration = RecordingStudioApi.instance_variable_get(:@configuration)
        configured = RecordingStudioApi::Configuration.new
        configured.openapi_description = "API surface for host applications"
        RecordingStudioApi.instance_variable_set(:@configuration, configured)

        document = OpenapiDocument.call

        assert_equal "API surface for host applications", document.fetch(:info).fetch(:description)
      ensure
        if original_configuration_defined
          RecordingStudioApi.instance_variable_set(:@configuration, original_configuration)
        else
          RecordingStudioApi.remove_instance_variable(:@configuration) if RecordingStudioApi.instance_variable_defined?(:@configuration)
        end
      end

      def test_token_operation_includes_request_body_and_no_auth_requirement
        document = OpenapiDocument.call
        token_operation = document.fetch(:paths).fetch("/recording_studio_api/oauth/token").fetch("post")

        assert_equal [], token_operation.fetch(:security)
        assert_equal "Exchange OAuth client credentials", token_operation.fetch(:summary)
        assert token_operation.key?(:requestBody)
        assert_equal %w[grant_type],
                     token_operation.dig(:requestBody, :content, "application/x-www-form-urlencoded", :schema, :required)
        assert token_operation.fetch(:responses).key?("200")
        assert token_operation.fetch(:responses).key?("400")
        assert token_operation.fetch(:responses).key?("401")
        assert token_operation.fetch(:responses).key?("429")

        revoke_operation = document.fetch(:paths).fetch("/recording_studio_api/oauth/revoke").fetch("post")
        assert_equal [], revoke_operation.fetch(:security)
        assert_equal "Revoke an OAuth access token", revoke_operation.fetch(:summary)
        assert revoke_operation.fetch(:responses).key?("200")
      end

      def test_resource_operations_include_security_and_path_parameters
        document = with_recordable_types(["Workspace"]) { OpenapiDocument.call }
        resource_item_operations = document.fetch(:paths).fetch("/recording_studio_api/api/v1/workspaces/{id}")
        show_operation = resource_item_operations.fetch("get")
        delete_operation = resource_item_operations.fetch("delete")

        assert_equal [{ bearerAuth: [] }], show_operation.fetch(:security)
        assert_includes show_operation.fetch(:parameters), {
          "name" => "id",
          "in" => "path",
          "required" => true,
          "description" => "Resource identifier.",
          "schema" => { "type" => "string" }
        }
        assert show_operation.fetch(:responses).key?("404")
        assert_equal [{ bearerAuth: [] }], delete_operation.fetch(:security)
        assert_includes delete_operation.fetch(:parameters), {
          "name" => "id",
          "in" => "path",
          "required" => true,
          "description" => "Resource identifier.",
          "schema" => { "type" => "string" }
        }
        assert delete_operation.fetch(:responses).key?("200")
      end

      def test_resource_tags_have_an_accessible_default_description
        document = with_recordable_types(["Page"]) { OpenapiDocument.call }

        assert_includes document.fetch(:tags), {
          name: "Page",
          description: "View and manage pages available to your client."
        }
      end

      def test_resource_tag_description_can_be_customized_in_openapi_metadata
        with_recordable_registration(
          "Page",
          openapi: {
            tag: {
              description: "Create and organize the content pages in a workspace."
            }
          }
        ) do
          document = with_recordable_types(["Page"]) { OpenapiDocument.call }

          assert_includes document.fetch(:tags), {
            name: "Page",
            description: "Create and organize the content pages in a workspace."
          }
        end
      end

      def test_resource_operations_respect_recordable_operation_allowlists
        document = with_recordable_registration("Workspace", openapi: {}, operations: %i[index]) do
          with_recordable_types(["Workspace"]) { OpenapiDocument.call }
        end

        collection_operations = document.fetch(:paths).fetch("/recording_studio_api/api/v1/workspaces")

        assert_equal ["get"], collection_operations.keys
        assert_not document.fetch(:paths).key?("/recording_studio_api/api/v1/workspaces/{id}")
      end

      def test_generated_resource_docs_describe_registration_without_inventing_fields
        fields = { summary: { resolver: ->(*) { "Summary" }, include: :request } }
        relationships = {
          comments: {
            source: :children, child_type: "Comment", many: true, include: :request,
            serializer: ->(*) { { body: "Body" } }, output_keys: %i[body], limit: 20
          }
        }

        with_recordable_registration(
          "Page",
          serializer: ->(*) { { title: "Page" } },
          output_keys: %i[title],
          fields: fields,
          relationships: relationships,
          sortable_attributes: %i[title],
          writable_attributes: %i[title],
          openapi: {}
        ) do
          document = with_recordable_types(["Page"]) { OpenapiDocument.call }
          collection = document.fetch(:paths).fetch("/recording_studio_api/api/v1/pages")
          item = document.fetch(:paths).fetch("/recording_studio_api/api/v1/pages/{id}")
          index_operation = collection.fetch("get")
          create_operation = collection.fetch("post")
          show_operation = item.fetch("get")
          update_operation = item.fetch("patch")
          delete_operation = item.fetch("delete")

          assert_equal "List pages", index_operation.fetch(:summary)
          assert_equal "Get a page", show_operation.fetch(:summary)
          assert_equal "Create a page", create_operation.fetch(:summary)
          assert_equal "Update a page", update_operation.fetch(:summary)
          assert_equal "Delete a page", delete_operation.fetch(:summary)

          index_description = index_operation.fetch(:description)
          assert_includes index_description, "Returns pages the caller can access."
          assert_includes index_description, "`title`"
          assert_includes index_description, "`id`"
          assert_includes index_description, "Available filters: `q` and `filter[title]`."
          assert_includes index_description, "Paginate with `limit` and `pagination_token`."
          assert_includes index_description, "Set `count=true`"
          assert_includes index_description, "Optional `include` values: `summary` and `comments`."
          refute_includes index_description, "`status`"

          assert_includes create_operation.fetch(:description), "`Idempotency-Key`"
          assert_includes create_operation.fetch(:description), "`parent_id`"
          assert_includes create_operation.fetch(:description), "`title`"
          assert_includes create_operation.fetch(:description), "Requires edit access."
          refute_includes create_operation.fetch(:description), "the caller can access"
          assert_includes update_operation.fetch(:description), "Write `title`."
          assert_includes update_operation.fetch(:description), "Requires edit access."
          refute_includes update_operation.fetch(:description), "the caller can access"
          refute_includes update_operation.fetch(:description), "`parent_id`"
          assert_includes delete_operation.fetch(:description), "Permanently delete Page."
          refute_includes delete_operation.fetch(:description), "the caller can access"
        end
      end

      def test_generated_index_omits_q_when_the_type_has_no_filterable_attributes
        with_recordable_registration("Page", openapi: {}) do
          document = with_recordable_types(["Page"]) { OpenapiDocument.call }
          description = document.fetch(:paths).fetch("/recording_studio_api/api/v1/pages").fetch("get").fetch(:description)

          refute_includes description, "Available filters"
          refute_includes description, "`q`"
        end
      end

      def test_generated_create_omits_parent_id_for_root_types
        original_root_allowed = RecordingStudio::RecordableDeclarations.method(:root_allowed?)
        RecordingStudio::RecordableDeclarations.define_singleton_method(:root_allowed?) do |recordable_type|
          recordable_type.to_s == "Workspace"
        end

        with_recordable_registration(
          "Workspace",
          serializer: ->(*) { { name: "Workspace" } },
          output_keys: %i[name],
          writable_attributes: %i[name],
          openapi: {}
        ) do
          document = with_recordable_types(["Workspace"]) { OpenapiDocument.call }
          description = document.fetch(:paths).fetch("/recording_studio_api/api/v1/workspaces").fetch("post").fetch(:description)

          assert_includes description, "Write `name`."
          refute_includes description, "`parent_id`"
        end
      ensure
        RecordingStudio::RecordableDeclarations.define_singleton_method(:root_allowed?, original_root_allowed)
      end

      def test_openapi_action_overrides_replace_generated_summary_and_description
        relationships = {
          folders: {
            source: :children, child_type: "Folder", many: true, include: true,
            serializer: ->(*) { { name: "Folder" } }, output_keys: %i[name], limit: 20,
            endpoints: %i[index]
          }
        }

        with_recordable_registration(
          "Page",
          serializer: ->(*) { { title: "Page" } },
          output_keys: %i[title],
          relationships: relationships,
          openapi: {
            index: {
              summary: "Browse published pages",
              description: "Host-owned list copy."
            },
            show: {
              summary: "Get page details"
            }
          }
        ) do
          document = with_recordable_types(%w[Page Folder]) { OpenapiDocument.call }
          index_operation = document.fetch(:paths).fetch("/recording_studio_api/api/v1/pages").fetch("get")
          show_operation = document.fetch(:paths).fetch("/recording_studio_api/api/v1/pages/{id}").fetch("get")

          assert_equal "Browse published pages", index_operation.fetch(:summary)
          refute_includes index_operation.fetch(:description), "Returns pages the caller can access."
          assert_includes index_operation.fetch(:description), "Host-owned list copy."
          assert_includes index_operation.fetch(:description), "Each item in `records` includes `folders`"
          assert_equal "Get page details", show_operation.fetch(:summary)
          assert_includes show_operation.fetch(:description), "Returns a page the caller can access."
        end
      end

      def test_openapi_parameter_overrides_add_to_builtin_parameters
        with_recordable_registration(
          "Page",
          openapi: {
            index: {
              parameters: [
                {
                  name: "limit",
                  in: "query",
                  required: false,
                  description: "Host limit copy.",
                  schema: { type: "integer" }
                },
                {
                  name: "published",
                  in: "query",
                  required: false,
                  description: "Only published pages.",
                  schema: { type: "boolean" }
                }
              ]
            }
          }
        ) do
          document = with_recordable_types(["Page"]) { OpenapiDocument.call }
          parameters = document.fetch(:paths).fetch("/recording_studio_api/api/v1/pages").fetch("get").fetch(:parameters)
          limit_parameter = parameters.find { |parameter| parameter.fetch("name") == "limit" && parameter.fetch("in") == "query" }
          published_parameter = parameters.find { |parameter| parameter.fetch("name") == "published" }

          assert_equal "Host limit copy.", limit_parameter.fetch("description")
          assert_equal(1, parameters.count { |parameter| parameter.fetch("name") == "limit" })
          refute_nil(parameters.find { |parameter| parameter.fetch("name") == "q" })
          refute_nil(parameters.find { |parameter| parameter.fetch("name") == "pagination_token" })
          assert_equal "Only published pages.", published_parameter.fetch("description")
        end
      end

      def test_parameter_override_without_in_matches_query_builtins
        with_recordable_registration(
          "Page",
          openapi: {
            index: {
              parameters: [
                { name: "limit", description: "Host limit without in.", schema: { type: "integer" } }
              ]
            }
          }
        ) do
          document = with_recordable_types(["Page"]) { OpenapiDocument.call }
          parameters = document.fetch(:paths).fetch("/recording_studio_api/api/v1/pages").fetch("get").fetch(:parameters)
          limit_parameters = parameters.select { |parameter| parameter.fetch("name") == "limit" }

          assert_equal 1, limit_parameters.length
          assert_equal "query", limit_parameters.first.fetch("in")
          assert_equal "Host limit without in.", limit_parameters.first.fetch("description")
        end
      end

      def test_empty_parameters_override_keeps_builtin_parameters
        with_recordable_registration(
          "Page",
          openapi: {
            index: {
              parameters: []
            }
          }
        ) do
          document = with_recordable_types(["Page"]) { OpenapiDocument.call }
          names = document.fetch(:paths).fetch("/recording_studio_api/api/v1/pages").fetch("get").fetch(:parameters)
                         .map { |parameter| parameter.fetch("name") }

          assert_includes names, "limit"
          assert_includes names, "pagination_token"
          assert_includes names, "q"
          refute_empty names
        end
      end

      def test_operation_for_passes_through_deprecated_and_external_docs
        with_recordable_registration(
          "Page",
          openapi: {
            show: {
              deprecated: true,
              externalDocs: {
                url: "https://example.test/pages",
                description: "Page guide"
              }
            }
          }
        ) do
          document = with_recordable_types(["Page"]) { OpenapiDocument.call }
          show_operation = document.fetch(:paths).fetch("/recording_studio_api/api/v1/pages/{id}").fetch("get")

          assert_equal true, show_operation.fetch(:deprecated)
          assert_equal(
            { url: "https://example.test/pages", description: "Page guide" },
            show_operation.fetch(:externalDocs)
          )
          refute document.fetch(:paths).fetch("/recording_studio_api/api/v1/pages").fetch("get").key?(:deprecated)
        end
      end

      def test_tag_groups_are_omitted_when_no_registration_declares_a_group
        document = with_recordable_types(["Page"]) { OpenapiDocument.call }

        refute document.key?(:"x-tagGroups")
      end

      def test_tag_groups_nest_declared_tags_and_keep_ungrouped_tags_visible
        with_recordable_registration("PressKit", openapi: { tag: { group: "Press kits" } }) do
          with_recordable_registration("Section", openapi: { tag: { group: "Press kits" } }) do
            with_recordable_registration("Video", openapi: { tag: { group: "Press kits" } }) do
              with_recordable_registration("Page", openapi: {}) do
                document = with_recordable_types(%w[PressKit Section Video Page]) { OpenapiDocument.call }
                groups = document.fetch(:"x-tagGroups")
                tag_names = document.fetch(:tags).map { |tag| tag.fetch(:name) }
                grouped_tags = ["Press Kit", "Section", "Video"]
                ungrouped_tags = tag_names - grouped_tags
                api_group = groups.fetch(0)
                press_kits = groups.find { |group| group.fetch(:name) == "Press kits" }
                tags_by_group = groups.to_h { |group| [group.fetch(:name), group.fetch(:tags)] }

                assert_equal "API", api_group.fetch(:name)
                assert_equal ungrouped_tags, api_group.fetch(:tags)
                assert_equal grouped_tags, press_kits.fetch(:tags)
                refute_includes tags_by_group.fetch("API"), "Press Kit"
                refute(groups.any? { |group| group.fetch(:name) == "Page" })
                groups.each do |group|
                  tags = group.fetch(:tags)
                  refute_equal [group.fetch(:name)], tags
                end
                assert_equal tag_names.sort, groups.flat_map { |group| group.fetch(:tags) }.sort
                tag_names.each do |name|
                  memberships = groups.count { |group| group.fetch(:tags).include?(name) }
                  assert_equal 1, memberships
                end
              end
            end
          end
        end
      end

      def test_delete_operation_description_mentions_permanent_delete
        with_stubbed_recordable_class("Page", [column_stub("id", :uuid, false)]) do
          with_recordable_registration("Page", openapi: {}, operations: %i[index show create update destroy]) do
            document = with_recordable_types(["Page"]) { OpenapiDocument.call }
            delete_operation = document.fetch(:paths).fetch("/recording_studio_api/api/v1/pages/{id}").fetch("delete")

            assert_equal(
              "Permanently delete Page. Recording Studio API hard-deletes the recording and recordable; it does not soft-delete or move to trash.",
              delete_operation.fetch(:description)
            )
          end
        end
      end

      def test_call_uses_configured_default_api_version_in_paths
        original_version = RecordingStudioApi.configuration.default_api_version

        RecordingStudioApi.configuration.default_api_version = "v2"
        document = with_recordable_types(["Workspace"]) { OpenapiDocument.call }

        assert document.fetch(:paths).key?("/recording_studio_api/api/v2")
        assert document.fetch(:paths).key?("/recording_studio_api/api/v2/workspaces")
      ensure
        RecordingStudioApi.configuration.default_api_version = original_version
      end

      def test_call_accepts_explicit_version_argument
        original_versions = RecordingStudioApi.configuration.api_versions
        original_version = RecordingStudioApi.configuration.default_api_version

        RecordingStudioApi.configuration.api_versions = %w[v1 v2]
        RecordingStudioApi.configuration.default_api_version = "v1"

        document = with_recordable_types(["Workspace"]) { OpenapiDocument.call(version: "v2") }

        assert document.fetch(:paths).key?("/recording_studio_api/api/v2/workspaces")
        refute document.fetch(:paths).key?("/recording_studio_api/api/v1/workspaces")
      ensure
        RecordingStudioApi.configuration.api_versions = original_versions
        RecordingStudioApi.configuration.default_api_version = original_version
      end

      def test_call_passes_mount_context_to_documentation_catalog
        original_versions = RecordingStudioApi.configuration.api_versions
        original_version = RecordingStudioApi.configuration.default_api_version
        RecordingStudioApi.configuration.api_versions = %w[v1 v2]

        document = with_recordable_types(["Workspace"]) do
          OpenapiDocument.call(
            version: "v2",
            mount_path: "/platform/recording-api",
            api_mount_path: "/public-api"
          )
        end

        assert document.fetch(:paths).key?("/platform/recording-api/oauth/token")
        assert document.fetch(:paths).key?("/platform/recording-api/public-api/v2/workspaces")

        token_operation = document.fetch(:paths).fetch("/platform/recording-api/oauth/token").fetch("post")
        assert_equal [], token_operation.fetch(:security)
        assert token_operation.fetch(:responses).key?("400")
        assert token_operation.fetch(:responses).key?("401")
        assert token_operation.fetch(:responses).key?("429")
        assert_not token_operation.fetch(:responses).key?("403")
        assert_not token_operation.fetch(:responses).key?("422")
        assert_equal "/platform/recording-api/oauth/token",
                     document.fetch(:components).fetch(:securitySchemes).fetch(:oauthClientCredentials)
                       .fetch(:flows).fetch(:clientCredentials).fetch(:tokenUrl)
      ensure
        RecordingStudioApi.configuration.api_versions = original_versions
        RecordingStudioApi.configuration.default_api_version = original_version
      end

      def test_resource_list_operation_includes_cursor_pagination_contract
        document = with_recordable_types(["Workspace"]) { OpenapiDocument.call }
        list_operation = document.fetch(:paths).fetch("/recording_studio_api/api/v1/workspaces").fetch("get")

        assert_includes list_operation.fetch(:parameters), {
          "name" => "limit",
          "in" => "query",
          "required" => false,
          "description" => "Maximum number of resources to return (default: 50).",
          "schema" => {
            "type" => "integer",
            "minimum" => 1,
            "default" => 50,
            "maximum" => 100
          }
        }
        assert_includes list_operation.fetch(:parameters), {
          "name" => "pagination_token",
          "in" => "query",
          "required" => false,
          "description" => "Pagination token from the previous response. Leave blank on the first request, then pass next_pagination_token from the prior response as pagination_token to fetch the next results.",
          "schema" => {
            "type" => "string"
          }
        }
        sort_parameter = list_operation.fetch(:parameters).find { |parameter| parameter["name"] == "sort" }
        refute_nil sort_parameter
        assert_equal "query", sort_parameter.fetch("in")
        assert_equal false, sort_parameter.fetch("required")
        assert_equal "Sort field for this resource.", sort_parameter.fetch("description")
        assert_equal "string", sort_parameter.fetch("schema").fetch("type")
        assert_includes sort_parameter.fetch("schema").fetch("enum"), "created_at"
        assert_equal "created_at", sort_parameter.fetch("schema").fetch("default")

        list_schema = list_operation
          .fetch(:responses)
          .fetch("200")
          .fetch("content")
          .fetch("application/json")
          .fetch("schema")
        list_branch = schema_branch(list_schema, "Resource list")
        count_branch = schema_branch(list_schema, "Count")

        assert_equal %w[resource type records meta], list_branch.fetch("required")
        assert_equal %w[limit sort order has_more next_pagination_token total_count],
                     list_branch.fetch("properties").fetch("meta").fetch("required")
        assert_equal ["total_count"], count_branch.fetch("required")
        assert_equal false, count_branch.fetch("additionalProperties")
        assert_equal ["total_count"], count_branch.fetch("properties").keys
        assert_equal(
          {
            "name" => "count",
            "in" => "query",
            "required" => false,
            "description" => "Set to true to get only { total_count } for the same filters. Records are not loaded; " \
                             "limit, sort, order, and pagination_token are ignored.",
            "schema" => { "type" => "boolean", "default" => false }
          },
          list_operation.fetch(:parameters).find { |parameter| parameter.fetch("name") == "count" }
        )
      end

      def test_capability_actions_generate_nested_resource_paths
        document = with_recordable_types_and_actions(
          ["Folder"],
          "Folder" => [action_stub(name: "move", http_verb: :post, capability: :movable, scope: :member)]
        ) do
          OpenapiDocument.call
        end

        move_operation = document.fetch(:paths).fetch("/recording_studio_api/api/v1/folders/{id}/actions/move").fetch("post")

        assert_equal ["Folder"], move_operation.fetch(:tags)
      end

      def test_openapi_includes_auto_enabled_capability_actions_and_excludes_opted_out_ones
        with_isolated_configuration do
          singleton = RecordingStudioApi.singleton_class
          original_recordable_types = RecordingStudioApi.method(:api_recordable_types)
          singleton.send(:define_method, :api_recordable_types) { %w[Page Folder] }

          RecordingStudioApi.register_capability_action(
            :shout,
            capability: :echoable,
            http_verb: :post,
            handler: ->(_context) { :ok }
          )
          RecordingStudioApi.register_recordable_type_api("Page")
          RecordingStudioApi.register_recordable_type_api(
            "Folder",
            capability_actions: %i[publish],
            auto_capability_actions: false
          )

          RecordingStudio.stub(:capability_enabled?, ->(capability, **) { capability == :echoable }) do
            paths = OpenapiDocument.call.fetch(:paths).keys

            assert_includes paths, "/recording_studio_api/api/v1/pages/{id}/actions/shout"
            refute_includes paths, "/recording_studio_api/api/v1/folders/{id}/actions/shout"
          end
        ensure
          singleton.send(:define_method, :api_recordable_types, original_recordable_types)
        end
      end

      def test_components_only_include_shared_schemas
        document = with_recordable_types(["Page"]) { OpenapiDocument.call }

        schemas = document.fetch(:components).fetch(:schemas)

        refute schemas.key?(:Recording)
        refute schemas.key?(:PageDetails)
        refute schemas.key?(:PageRecording)
      end

      def test_resource_response_schema_parent_id_is_nullable_with_non_null_example
        document = with_recordable_types(["Workspace"]) { OpenapiDocument.call }
        parent_schema = document
          .fetch(:paths)
          .fetch("/recording_studio_api/api/v1/workspaces/{id}")
          .fetch("get")
          .fetch(:responses)
          .fetch("200")
          .fetch("content")
          .fetch("application/json")
          .fetch("schema")
          .fetch("properties")
          .fetch("parent_id")

        assert_equal true, parent_schema.fetch("nullable")
        refute_nil parent_schema.fetch("example")
      end

      def test_resource_response_schema_has_flat_canonical_keys_without_actions
        document = with_recordable_types(["Workspace"]) { OpenapiDocument.call }
        schema = document
          .fetch(:paths)
          .fetch("/recording_studio_api/api/v1/workspaces/{id}")
          .fetch("get")
          .fetch(:responses)
          .fetch("200")
          .fetch("content")
          .fetch("application/json")
          .fetch("schema")

        assert_equal %w[id type root_id parent_id created_at updated_at], schema.fetch("properties").keys.map(&:to_s) & %w[id type root_id parent_id created_at updated_at]
        refute schema.fetch("properties").key?("actions")
      end

      def test_flat_schema_documents_serializer_fields_relationships_and_meta
        relationships = {
          folders: {
            source: :children, child_type: "Folder", many: true, include: true,
            serializer: ->(*) { { label: "Folder" } }, output_keys: %i[label], limit: 20,
            endpoints: %i[index]
          },
          owner: {
            source: :custom, many: false, include: true, resolver: ->(*) {},
            serializer: ->(*) { { name: "Owner" } }, output_keys: %i[name]
          }
        }
        fields = { title: { resolver: ->(*) { "Title" }, include: true, openapi: { type: :string } } }

        with_recordable_registration("Page", serializer: ->(*) { { slug: "page" } }, output_keys: %i[slug], fields: fields, relationships: relationships, openapi: {}) do
          document = with_recordable_types(%w[Page Folder]) { OpenapiDocument.call }
          properties = document.dig(:paths, "/recording_studio_api/api/v1/pages/{id}", "get", :responses, "200", "content", "application/json", "schema", "properties")

          assert_equal "string", properties.fetch("slug").fetch("type")
          assert_equal "string", properties.fetch("title").fetch("type")
          assert_equal "array", properties.fetch("folders").fetch("type")
          assert_equal true, properties.fetch("owner").fetch("nullable")
          assert_equal %w[limit has_more], properties.fetch("_meta").fetch("properties").fetch("folders").fetch("required")
        end
      end

      def test_include_parameter_only_documents_request_enabled_registered_names
        fields = { summary: { resolver: ->(*) { "Summary" }, include: :request } }
        relationships = {
          comments: {
            source: :children, child_type: "Comment", many: true, include: :request,
            serializer: ->(*) { { body: "Body" } }, output_keys: %i[body], limit: 20
          },
          author: {
            source: :custom, many: false, include: true, resolver: ->(*) {},
            serializer: ->(*) { { name: "Author" } }, output_keys: %i[name]
          }
        }

        with_recordable_registration("Page", fields: fields, relationships: relationships, openapi: {}) do
          document = with_recordable_types(["Page"]) { OpenapiDocument.call }
          parameters = document.dig(:paths, "/recording_studio_api/api/v1/pages", "get", :parameters)
          include_parameter = parameters.find { |parameter| parameter.fetch("name") == "include" }

          assert_equal "summary,comments", include_parameter.fetch("schema").fetch("example")
          refute include_parameter.fetch("schema").key?("enum")
          assert_includes include_parameter.fetch("description"), "summary, comments"
          refute_includes include_parameter.fetch("description"), "true"
        end
      end

      def test_relationship_get_documentation_generates_descriptions_and_examples
        relationships = {
          folders: {
            source: :children, child_type: "Folder", many: true, include: true,
            serializer: ->(*) { { name: "Folder" } }, output_keys: %i[name], limit: 20,
            endpoints: %i[index show], description: "The folders directly inside this workspace."
          },
          pages: {
            source: :children, child_type: "Page", many: true, include: :request,
            serializer: ->(*) { { title: "Page" } }, output_keys: %i[title], limit: 20,
            endpoints: %i[index show], description: "The pages directly inside this workspace."
          },
          featured_folder: {
            source: :custom, many: false, include: :request, resolver: ->(*) {},
            serializer: ->(*) { { name: "Folder" } }, output_keys: %i[name],
            description: "The first Folder directly inside this workspace."
          }
        }

        with_recordable_registration(
          "Workspace",
          relationships: relationships,
          openapi: {
            show: {
              responses: {
                "200" => {
                  content: {
                    "application/json" => {
                      examples: {
                        host_example: { value: { id: "host-controlled-example" } }
                      }
                    }
                  }
                }
              }
            }
          }
        ) do
          document = with_recordable_types(%w[Workspace Folder Page]) { OpenapiDocument.call }
          operation = document.fetch(:paths).fetch("/recording_studio_api/api/v1/workspaces/{id}").fetch("get")
          response_examples = operation.fetch(:responses).fetch("200").fetch("content").fetch("application/json").fetch("examples")

          assert_includes operation.fetch(:description), "The response includes `folders`, an array of Folder records with `name` (up to 20). The folders directly inside this workspace."
          assert_includes operation.fetch(:description), "Add `include=pages` to also receive `pages`, an array of Page records with `title` (up to 20). The pages directly inside this workspace."
          assert_includes operation.fetch(:description), "Add `include=featured_folder` to also receive `featured_folder`, one related record or `null` with `name`. The first Folder directly inside this workspace."
          assert_includes operation.fetch(:description), "To browse folders separately, use `GET /recording_studio_api/api/v1/workspaces/{id}/folders`."
          assert_includes operation.fetch(:description), "`featured_folder` is available only in this response; there is no separate endpoint for it."
          assert response_examples.key?("default_relationships")
          assert_equal "Workspace with included fields", response_examples.fetch("default_relationships").fetch("summary")
          assert_equal "Workspace with requested details", response_examples.fetch("requested_relationships").fetch("summary")
          assert_equal "host-controlled-example", response_examples.fetch("host_example").fetch("value").fetch("id")
          folder_types = response_examples.fetch("default_relationships").fetch("value").fetch("folders").map { |folder| folder.fetch("type") }
          assert_equal ["Folder"], folder_types
          refute response_examples.fetch("default_relationships").fetch("value").key?("pages")
          page_types = response_examples.fetch("requested_relationships").fetch("value").fetch("pages").map { |page| page.fetch("type") }
          assert_equal ["Page"], page_types
          assert_equal "Custom relationship", response_examples.fetch("requested_relationships").fetch("value").fetch("featured_folder").fetch("type")
        end
      end

      def test_nested_index_uses_the_standard_paginated_collection_contract
        relationships = {
          folders: {
            source: :children, child_type: "Folder", many: true, serializer: ->(*) { { name: "Folder" } },
            output_keys: %i[name], limit: 20, endpoints: %i[index]
          }
        }

        with_recordable_registration("Workspace", relationships: relationships, openapi: {}) do
          with_recordable_registration("Folder", openapi: {}) do
            document = with_recordable_types(%w[Workspace Folder]) { OpenapiDocument.call }
            normal_schema = document.dig(:paths, "/recording_studio_api/api/v1/folders", "get", :responses, "200", "content", "application/json", "schema")
            nested_operation = document.dig(:paths, "/recording_studio_api/api/v1/workspaces/{id}/folders", "get")
            nested_schema = nested_operation.dig(:responses, "200", "content", "application/json", "schema")
            normal_list = schema_branch(normal_schema, "Resource list")
            nested_list = schema_branch(nested_schema, "Resource list")
            normal_count = schema_branch(normal_schema, "Count")
            nested_count = schema_branch(nested_schema, "Count")

            assert_equal normal_list.fetch("required"), nested_list.fetch("required")
            assert_equal normal_list.fetch("properties").keys.sort, nested_list.fetch("properties").keys.sort
            assert_equal normal_list.fetch("properties").fetch("meta").fetch("required"),
                         nested_list.fetch("properties").fetch("meta").fetch("required")
            assert_equal normal_count.fetch("required"), nested_count.fetch("required")
            refute nested_list.fetch("properties").key?("relationship")
            assert_equal false, nested_list.fetch("properties").fetch("meta").fetch("properties").key?("filter")
            assert_equal true, nested_list.fetch("properties").fetch("meta").fetch("properties").key?("total_count")
            assert_equal true, normal_list.fetch("properties").fetch("meta").fetch("properties").key?("filter")
            assert_equal "string", nested_list.fetch("properties").fetch("records").fetch("items").fetch("properties").fetch("name").fetch("type")

            count_parameter = document.dig(:paths, "/recording_studio_api/api/v1/folders", "get", :parameters)
                                      .find { |parameter| parameter.fetch("name") == "count" }
            nested_count_parameter = nested_operation.fetch(:parameters).find { |parameter| parameter.fetch("name") == "count" }
            assert_equal count_parameter, nested_count_parameter
            assert_includes nested_operation.fetch(:parameters).map { |parameter| parameter.fetch("name") }, "limit"
            assert_includes nested_operation.fetch(:parameters).map { |parameter| parameter.fetch("name") }, "pagination_token"
          end
        end
      end

      def test_named_api_nested_paths_are_isolated_and_respect_child_operations
        original_configuration = RecordingStudioApi.configuration
        configuration = RecordingStudioApi::Configuration.new
        RecordingStudioApi.instance_variable_set(:@configuration, configuration)
        configuration.recordable_registry.register(
          "Workspace",
          relationships: {
            public_folders: { source: :children, child_type: "Folder", many: true, serializer: ->(*) {},
                              output_keys: %i[name], limit: 20, endpoints: %i[index] }
          }
        )
        operations = configuration.api(:operations)
        operations.recordable_registry.register(
          "Workspace",
          relationships: {
            folders: { source: :children, child_type: "Folder", many: true, serializer: ->(*) {},
                       output_keys: %i[name], limit: 20, endpoints: %i[index create] }
          }
        )
        operations.recordable_registry.register("Folder", operations: %i[index])

        document = OpenapiDocument.call(api: :operations)
        paths = document.fetch(:paths).keys

        assert_includes paths, "/recording_studio_api/apis/operations/v1/workspaces/{id}/folders"
        refute(paths.any? { |path| path.include?("public_folders") })
        refute document.fetch(:paths).fetch("/recording_studio_api/apis/operations/v1/workspaces/{id}/folders").key?("post")
      ensure
        RecordingStudioApi.instance_variable_set(:@configuration, original_configuration)
      end

      def test_generated_document_is_json_structurally_valid
        document = with_recordable_types(["Workspace"]) { OpenapiDocument.call }

        assert_equal "3.0.3", JSON.parse(JSON.generate(document)).fetch("openapi")
      end

      def test_registered_enum_attribute_is_documented_as_named_enum
        with_recordable_registration(
          "Page",
          serializer: ->(*) { { role: "view" } },
          output_keys: %i[role],
          openapi: {
            details_schema: {
              type: "object",
              properties: {
                role: {
                  type: "string",
                  enum: %w[view edit admin],
                  example: "view"
                }
              }
            }
          }
        ) do
          document = with_recordable_types(["Page"]) { OpenapiDocument.call }
          role_schema = document
            .fetch(:paths)
            .fetch("/recording_studio_api/api/v1/pages/{id}")
            .fetch("get")
            .fetch(:responses)
            .fetch("200")
            .fetch("content")
            .fetch("application/json")
            .fetch("schema")
            .fetch("properties")
            .fetch("role")

          assert_equal "string", role_schema.fetch("type")
          assert_equal %w[view edit admin], role_schema.fetch("enum")
          assert_equal "view", role_schema.fetch("example")
        end
      end

      def test_resource_list_meta_example_is_coherent
        document = with_recordable_types(["Workspace"]) { OpenapiDocument.call }
        meta_schema = schema_branch(
          document
            .fetch(:paths)
            .fetch("/recording_studio_api/api/v1/workspaces")
            .fetch("get")
            .fetch(:responses)
            .fetch("200")
            .fetch("content")
            .fetch("application/json")
            .fetch("schema"),
          "Resource list"
        ).fetch("properties").fetch("meta")

        assert_equal false, meta_schema.fetch("example").fetch("has_more")
        assert_nil meta_schema.fetch("example").fetch("next_pagination_token")
        assert_equal 2, meta_schema.fetch("example").fetch("total_count")
      end

      def test_unregistered_page_schema_has_no_attributes_wrapper
        with_stubbed_recordable_class("Page", [
                                      column_stub("id", :uuid, false),
                                      column_stub("title", :string, true),
                                      column_stub("created_at", :datetime, false)
                                    ]) do
          document = with_recordable_types(["Page"]) { OpenapiDocument.call }
          properties = document
            .fetch(:paths)
            .fetch("/recording_studio_api/api/v1/pages/{id}")
            .fetch("get")
            .fetch(:responses)
            .fetch("200")
            .fetch("content")
            .fetch("application/json")
            .fetch("schema")
            .fetch("properties")

          refute properties.key?("attributes")
          assert_equal "string", properties.fetch("created_at").fetch("type")
          assert_equal "string", properties.fetch("updated_at").fetch("type")
        end
      end

      def test_registered_endpoints_are_tagged_separately_from_recordable_resources
        document = with_isolated_configuration do
          RecordingStudioApi.register_endpoint(
            :ping,
            http_verb: :get,
            path: "ping",
            handler: ->(_context) { { ok: true } }
          )
          OpenapiDocument.call
        end

        ping = document.fetch(:paths).fetch("/recording_studio_api/api/v1/ping").fetch("get")
        assert_equal ["Endpoints"], ping.fetch(:tags)
        assert_includes document.fetch(:tags), {
          name: "Endpoints",
          description: "Named routes that are not a tree collection."
        }
      end

      def test_registered_endpoint_path_parameter_description_appears_once
        document = with_isolated_configuration do
          RecordingStudioApi.register_endpoint(
            :show_item,
            http_verb: :get,
            path: "items/:id",
            handler: ->(_context) { { ok: true } },
            openapi: {
              parameters: [
                { name: "id", in: "path", description: "The item." },
                { name: "verbose", in: "query", description: "Include extras.", schema: { type: "boolean" } }
              ]
            }
          )
          RecordingStudioApi.register_endpoint(
            :describe_widget,
            http_verb: :get,
            path: "widgets/:key",
            handler: ->(_context) { { ok: true } }
          )
          OpenapiDocument.call
        end

        described = document.fetch(:paths).fetch("/recording_studio_api/api/v1/items/{id}").fetch("get").fetch(:parameters)
        undescribed = document.fetch(:paths).fetch("/recording_studio_api/api/v1/widgets/{key}").fetch("get").fetch(:parameters)
        id_parameters = described.select { |parameter| parameter.fetch("name") == "id" }
        verbose = described.find { |parameter| parameter.fetch("name") == "verbose" }
        key_parameters = undescribed.select { |parameter| parameter.fetch("name") == "key" }

        assert_equal 1, id_parameters.length
        assert_equal "path", id_parameters.first.fetch("in")
        assert_equal true, id_parameters.first.fetch("required")
        assert_equal "The item.", id_parameters.first.fetch("description")
        assert_equal "query", verbose.fetch("in")
        assert_equal "Include extras.", verbose.fetch("description")
        assert_equal 1, key_parameters.length
        assert_equal "path", key_parameters.first.fetch("in")
        refute key_parameters.first.key?("description")
      end

      def test_metrics_openapi_documents_period_aliases_group_by_and_resource
        document = with_isolated_configuration do
          RecordingStudioMetrics::Api.register!(api: :operations)
          OpenapiDocument.call(api: :operations)
        end
        root = "/recording_studio_api/apis/operations/v1"
        catalog = document.fetch(:paths).fetch("#{root}/metrics").fetch("get")
        show = document.fetch(:paths).fetch("#{root}/metrics/{resource}/{name}").fetch("get")
        alias_catalog = document.fetch(:paths).fetch("#{root}/{resource}/metrics").fetch("get")
        alias_show = document.fetch(:paths).fetch("#{root}/{resource}/metrics/{name}").fetch("get")

        show_query = query_parameter_names(show)
        %w[start end start_at end_at from to group_by].each do |name|
          assert_equal 1, show_query.count(name), name
        end
        from_parameter = show.fetch(:parameters).find { |parameter| parameter.fetch("name") == "from" }
        assert_equal "Alias for start. Must match start when both are provided.", from_parameter.fetch("description")
        assert_equal "date-time", from_parameter.fetch("schema").fetch("format")
        assert_equal "query", from_parameter.fetch("in")
        refute_includes show_query, "resource"
        refute_includes query_parameter_names(alias_show), "resource"
        assert_equal %w[resource name], path_parameter_names(alias_show)

        assert_equal 1, query_parameter_names(catalog).count("resource")
        resource_parameter = catalog.fetch(:parameters).find { |parameter| parameter.fetch("name") == "resource" }
        assert_equal "query", resource_parameter.fetch("in")
        assert_equal "Only list metrics for this resource.", resource_parameter.fetch("description")
        refute_includes query_parameter_names(alias_catalog), "resource"
        assert_equal ["resource"], path_parameter_names(alias_catalog)
      end

      private

      def schema_branch(schema, title)
        schema.fetch("oneOf").find { |branch| branch.fetch("title") == title }
      end

      def query_parameter_names(operation)
        operation.fetch(:parameters).select { |parameter| parameter.fetch("in") == "query" }.map { |parameter| parameter.fetch("name") }
      end

      def path_parameter_names(operation)
        operation.fetch(:parameters).select { |parameter| parameter.fetch("in") == "path" }.map { |parameter| parameter.fetch("name") }
      end

      def with_isolated_configuration
        original_configuration_defined = RecordingStudioApi.instance_variable_defined?(:@configuration)
        original_configuration = RecordingStudioApi.instance_variable_get(:@configuration)
        RecordingStudioApi.instance_variable_set(:@configuration, RecordingStudioApi::Configuration.new)
        yield
      ensure
        if original_configuration_defined
          RecordingStudioApi.instance_variable_set(:@configuration, original_configuration)
        elsif RecordingStudioApi.instance_variable_defined?(:@configuration)
          RecordingStudioApi.remove_instance_variable(:@configuration)
        end
      end

      def with_recordable_types(recordable_types)
        singleton = RecordingStudioApi.singleton_class
        original_recordable_types = RecordingStudioApi.method(:api_recordable_types)
        original_actions_for = RecordingStudioApi.method(:capability_actions_for)

        singleton.send(:define_method, :api_recordable_types) { recordable_types }
        singleton.send(:define_method, :capability_actions_for) do |_recordable_type, **|
          []
        end
        yield
      ensure
        singleton.send(:define_method, :api_recordable_types, original_recordable_types)
        singleton.send(:define_method, :capability_actions_for, original_actions_for)
      end

      def with_recordable_types_and_actions(recordable_types, actions_by_type)
        singleton = RecordingStudioApi.singleton_class
        original_recordable_types = RecordingStudioApi.method(:api_recordable_types)
        original_actions_for = RecordingStudioApi.method(:capability_actions_for)

        singleton.send(:define_method, :api_recordable_types) { recordable_types }
        singleton.send(:define_method, :capability_actions_for) do |recordable_type, **|
          actions_by_type.fetch(recordable_type, [])
        end
        yield
      ensure
        singleton.send(:define_method, :api_recordable_types, original_recordable_types)
        singleton.send(:define_method, :capability_actions_for, original_actions_for)
      end

      def action_stub(name:, http_verb:, capability:, scope:)
        Struct.new(:name, :http_verb, :capability, :scope, :openapi, keyword_init: true).new(
          name: name,
          http_verb: http_verb,
          capability: capability,
          scope: scope,
          openapi: {}
        )
      end

      def column_stub(name, type, nullable)
        Struct.new(:name, :type, :null).new(name, type, nullable)
      end

      def with_stubbed_recordable_class(class_name, columns, enums: {})
        existing_class = Object.const_get(class_name) if Object.const_defined?(class_name)
        Object.send(:remove_const, class_name) if existing_class

        klass = Class.new do
          define_singleton_method(:columns) { columns }
          define_singleton_method(:defined_enums) { enums }
        end
        Object.const_set(class_name, klass)

        yield
      ensure
        Object.send(:remove_const, class_name) if Object.const_defined?(class_name)
        Object.const_set(class_name, existing_class) if existing_class
      end

      def with_recordable_registration(recordable_type, openapi:, serializer: nil, output_keys: nil, fields: nil, relationships: nil, operations: nil, sortable_attributes: nil, writable_attributes: nil)
        registry = RecordingStudioApi.configuration.recordable_registry
        registrations = registry.instance_variable_get(:@registrations)
        key = recordable_type.to_s
        existing = registrations.delete(key)

        registry.register(
          recordable_type,
          serializer: serializer,
          output_keys: output_keys,
          fields: fields,
          relationships: relationships,
          openapi: openapi,
          operations: operations,
          sortable_attributes: sortable_attributes,
          writable_attributes: writable_attributes
        )
        yield
      ensure
        registrations.delete(key)
        registrations[key] = existing if existing
      end
    end
  end
end