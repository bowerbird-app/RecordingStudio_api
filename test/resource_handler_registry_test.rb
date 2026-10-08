# frozen_string_literal: true

require "test_helper"

class ResourceHandlerRegistryTest < Minitest::Test
  def setup
    @original_configuration = RecordingStudioApi.instance_variable_get(:@configuration)
    RecordingStudioApi.instance_variable_set(:@configuration, RecordingStudioApi::Configuration.new)
  end

  def teardown
    RecordingStudioApi.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_register_and_fetch_are_scoped_to_api_and_recordable_type
    page_create = ->(_context) { { json: { handled: "page-create" }, status: :created } }
    page_move = ->(_context) { { json: { handled: "page-move" }, status: :ok } }
    folder_create = ->(_context) { { json: { handled: "folder-create" }, status: :created } }
    operations_create = ->(_context) { { json: { handled: "operations-create" }, status: :created } }

    RecordingStudioApi.register_resource_handler("Page", :create, handler: page_create)
    RecordingStudioApi.register_resource_handler("Page", "move", handler: page_move)
    RecordingStudioApi.register_resource_handler("Folder", :create, handler: folder_create)
    RecordingStudioApi.register_resource_handler("Page", :create, api: :operations, handler: operations_create)

    assert_equal page_create, RecordingStudioApi.resource_handler("Page", "create")
    assert_equal page_move, RecordingStudioApi.resource_handler("Page", :move, api: :public)
    assert_equal folder_create, RecordingStudioApi.resource_handler("Folder", :create)
    assert_nil RecordingStudioApi.resource_handler("Folder", :move)
    assert_nil RecordingStudioApi.resource_handler("Workspace", :create)
    refute_equal page_create, RecordingStudioApi.resource_handler("Page", :create, api: :operations)
    assert_equal operations_create, RecordingStudioApi.resource_handler("Page", :create, api: :operations)
    assert_nil RecordingStudioApi.resource_handler("Folder", :create, api: :operations)
  end

  def test_duplicate_registration_and_missing_handler_are_rejected
    RecordingStudioApi.register_resource_handler("Page", :index, handler: ->(_context) { { json: {}, status: :ok } })

    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.register_resource_handler("Page", :index, handler: ->(_context) { { json: {}, status: :ok } })
    end
    assert_equal "Resource handler for Page index is already registered", error.message

    assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.register_resource_handler("Page", :show, handler: Object.new)
    end
    assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.register_resource_handler(" ", :show, handler: ->(_context) { {} })
    end
    assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.resource_handler("Page", :index, api: :missing)
    end
  end

  def test_configuration_snapshot_lists_registered_handlers
    RecordingStudioApi.register_resource_handler("Page", :update, handler: NamedResourceHandler)

    listed = RecordingStudioApi.configuration.to_h.fetch(:resource_handlers)
    assert_equal "ResourceHandlerRegistryTest::NamedResourceHandler", listed.fetch("Page").fetch("update")
  end

  class NamedResourceHandler
    def self.call(_context)
      { json: {}, status: :ok }
    end
  end
end
