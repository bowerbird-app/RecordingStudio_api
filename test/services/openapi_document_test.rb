# frozen_string_literal: true

require "test_helper"

module RecordingStudioApi
  module Services
    class OpenapiDocumentTest < Minitest::Test
      def test_call_builds_openapi_document_with_paths
        document = OpenapiDocument.call
        expected_title = Rails.application.class.module_parent_name.presence || "RecordingStudioApi"

        assert_equal "3.0.3", document.fetch(:openapi)
        assert_equal expected_title, document.fetch(:info).fetch(:title)
        assert document.fetch(:paths).key?("/recording_studio_api/oauth/token")
        assert document.fetch(:paths).key?("/recording_studio_api/api/v1")
        assert document.fetch(:components).fetch(:schemas).key?(:OAuthTokenResponse)
        assert document.fetch(:components).fetch(:responses).key?(:Unauthorized)
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
        assert token_operation.fetch(:responses).key?("200")
        assert token_operation.fetch(:responses).key?("401")
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

      def test_delete_operation_description_mentions_permanent_delete
        with_stubbed_recordable_class("Page", [column_stub("id", :uuid, false)], supports_trash: true) do
          document = with_recordable_types(["Page"]) { OpenapiDocument.call }
          delete_operation = document.fetch(:paths).fetch("/recording_studio_api/api/v1/pages/{id}").fetch("delete")

          assert_equal "Delete Page permanently", delete_operation.fetch(:description)
        end
      end

      def test_global_trash_endpoints_are_present
        document = with_recordable_types(["Page"]) { OpenapiDocument.call }

        assert document.fetch(:paths).key?("/recording_studio_api/api/v1/trash")
        assert document.fetch(:paths).key?("/recording_studio_api/api/v1/trash/{id}")
        assert document.fetch(:paths).key?("/recording_studio_api/api/v1/trash/{id}/restore")

        trash_delete = document
          .fetch(:paths)
          .fetch("/recording_studio_api/api/v1/trash/{id}")
          .fetch("delete")

        assert_equal "Permanently delete trashed", trash_delete.fetch(:description)
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
        assert token_operation.fetch(:responses).key?("422")
        assert_not token_operation.fetch(:responses).key?("403")
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

        assert_equal %w[resource type data meta], list_schema.fetch("required")
        assert_equal %w[limit sort order has_more next_pagination_token],
                     list_schema.fetch("properties").fetch("meta").fetch("required")
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

      def test_dummy_trash_capability_generates_a_nested_page_path
        document = with_recordable_types_and_actions(
          ["Page", "Workspace"],
          "Page" => [action_stub(name: "trash", http_verb: :post, capability: :trashable, scope: :member)],
          "Workspace" => []
        ) do
          OpenapiDocument.call
        end

        trash_operation = document
          .fetch(:paths)
          .fetch("/recording_studio_api/api/v1/pages/{id}/actions/trash")
          .fetch("post")

        assert_equal ["Page"], trash_operation.fetch(:tags)
        refute document.fetch(:paths).key?("/recording_studio_api/api/v1/workspaces/{id}/actions/trash")
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
          .fetch("data")
          .fetch("properties")
          .fetch("parent_id")

        assert_equal true, parent_schema.fetch("nullable")
        refute_nil parent_schema.fetch("example")
      end

      def test_resource_response_schema_actions_defaults_to_empty_array_example
        document = with_recordable_types(["Workspace"]) { OpenapiDocument.call }
        actions_schema = document
          .fetch(:paths)
          .fetch("/recording_studio_api/api/v1/workspaces/{id}")
          .fetch("get")
          .fetch(:responses)
          .fetch("200")
          .fetch("content")
          .fetch("application/json")
          .fetch("schema")
          .fetch("properties")
          .fetch("data")
          .fetch("properties")
          .fetch("actions")

        assert_equal [], actions_schema.fetch("example")
      end

      def test_registered_enum_attribute_is_documented_as_named_enum
        with_recordable_registration(
          "Page",
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
            .fetch("data")
            .fetch("properties")
            .fetch("attributes")
            .fetch("properties")
            .fetch("role")

          assert_equal "string", role_schema.fetch("type")
          assert_equal %w[view edit admin], role_schema.fetch("enum")
          assert_equal "view", role_schema.fetch("example")
        end
      end

      def test_resource_list_meta_example_is_coherent
        document = with_recordable_types(["Workspace"]) { OpenapiDocument.call }
        meta_schema = document
          .fetch(:paths)
          .fetch("/recording_studio_api/api/v1/workspaces")
          .fetch("get")
          .fetch(:responses)
          .fetch("200")
          .fetch("content")
          .fetch("application/json")
          .fetch("schema")
          .fetch("properties")
          .fetch("meta")

        assert_equal false, meta_schema.fetch("example").fetch("has_more")
        assert_nil meta_schema.fetch("example").fetch("next_pagination_token")
      end

      def test_unregistered_page_schema_uses_closed_attributes_schema
        with_stubbed_recordable_class("Page", [
                                      column_stub("id", :uuid, false),
                                      column_stub("title", :string, true),
                                      column_stub("created_at", :datetime, false)
                                    ]) do
          document = with_recordable_types(["Page"]) { OpenapiDocument.call }
          attributes_schema = document
            .fetch(:paths)
            .fetch("/recording_studio_api/api/v1/pages/{id}")
            .fetch("get")
            .fetch(:responses)
            .fetch("200")
            .fetch("content")
            .fetch("application/json")
            .fetch("schema")
            .fetch("properties")
            .fetch("data")
            .fetch("properties")
            .fetch("attributes")

          assert_equal "object", attributes_schema.fetch("type")
          assert_equal({}, attributes_schema.fetch("properties"))
          assert_equal false, attributes_schema.fetch("additionalProperties")
        end
      end

      private

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

      def with_stubbed_recordable_class(class_name, columns, supports_trash: false, enums: {})
        existing_class = Object.const_get(class_name) if Object.const_defined?(class_name)
        Object.send(:remove_const, class_name) if existing_class

        klass = Class.new do
          define_singleton_method(:columns) { columns }
          define_singleton_method(:defined_enums) { enums }
          define_method(:trash!) {} if supports_trash
        end
        Object.const_set(class_name, klass)

        yield
      ensure
        Object.send(:remove_const, class_name) if Object.const_defined?(class_name)
        Object.const_set(class_name, existing_class) if existing_class
      end

      def with_recordable_registration(recordable_type, openapi:)
        registry = RecordingStudioApi.configuration.recordable_registry
        existing = registry[recordable_type]

        registry.register(recordable_type, openapi: openapi)
        yield
      ensure
        registrations = registry.instance_variable_get(:@registrations)
        if existing
          registrations[recordable_type] = existing
        else
          registrations.delete(recordable_type)
        end
      end
    end
  end
end