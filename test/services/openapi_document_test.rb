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
        assert document.fetch(:components).fetch(:schemas).key?(:Recording)
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
        show_operation = document.fetch(:paths).fetch("/recording_studio_api/api/v1/workspaces/{id}").fetch("get")

        assert_equal [{ bearerAuth: [] }], show_operation.fetch(:security)
        assert_includes show_operation.fetch(:parameters), {
          "name" => "id",
          "in" => "path",
          "required" => true,
          "description" => "Resource identifier.",
          "schema" => { "type" => "string" }
        }
        assert show_operation.fetch(:responses).key?("404")
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

      def test_components_include_recordable_specific_schemas
        document = with_recordable_types(["Page"]) { OpenapiDocument.call }

        schemas = document.fetch(:components).fetch(:schemas)

        assert schemas.key?(:PageDetails)
        assert schemas.key?(:PageRecording)
        assert_equal "#/components/schemas/PageDetails", schemas.fetch(:PageRecording).fetch(:allOf).last.fetch(:properties).fetch(:attributes).fetch("$ref")
      end

      private

      def with_recordable_types(recordable_types)
        singleton = RecordingStudioApi.singleton_class
        original_recordable_types = RecordingStudioApi.method(:api_recordable_types)
        original_actions_for = RecordingStudioApi.method(:capability_actions_for)

        singleton.send(:define_method, :api_recordable_types) { recordable_types }
        singleton.send(:define_method, :capability_actions_for) { |_recordable_type| [] }
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
        singleton.send(:define_method, :capability_actions_for) do |recordable_type|
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
    end
  end
end