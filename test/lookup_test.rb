# frozen_string_literal: true

require "test_helper"

class LookupTest < Minitest::Test
  Serializer = ->(*) { { title: "Page" } }
  PageHandler = ->(_context) { :page }
  PublishHandler = ->(_context) { :publish }
  PingHandler = ->(_context) { { ok: true } }
  OpsPingHandler = ->(_context) { { ok: :ops } }

  def setup
    @original_configuration = RecordingStudioApi.instance_variable_get(:@configuration)
    RecordingStudioApi.instance_variable_set(:@configuration, RecordingStudioApi::Configuration.new)
    RecordingStudioApi.register_default_resource_actions!
  end

  def teardown
    RecordingStudioApi.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_public_type_operations_default_to_not_sensitive
    register_page

    show = RecordingStudioApi.lookup(api: :public, recordable_type: "Page", operation: :show)
    destroy = RecordingStudioApi.lookup(recordable_type: "Page", operation: :destroy)

    assert_equal RecordingStudioApi::Services::ResourceOperations::Show, show.handler
    assert_equal false, show.sensitive
    assert_equal %i[public], show.apis
    assert_equal RecordingStudioApi::Services::ResourceOperations::Destroy, destroy.handler
    assert_equal false, destroy.sensitive
  end

  def test_explicit_sensitive_operations_mark_only_those_names
    register_page(sensitive: %i[destroy])

    show = RecordingStudioApi.lookup(recordable_type: "Page", operation: :show)
    destroy = RecordingStudioApi.lookup(recordable_type: "Page", operation: :destroy)

    assert_equal false, show.sensitive
    assert_equal true, destroy.sensitive
  end

  def test_operations_api_type_operations_default_to_sensitive
    RecordingStudioApi.configuration.api(:operations)
    RecordingStudioApi.register_default_resource_actions!(api: :operations)
    RecordingStudioApi.register_recordable_type_api(
      "Page",
      api: :operations,
      operations: %i[index show destroy],
      serializer: Serializer,
      output_keys: %i[title]
    )

    show = RecordingStudioApi.lookup(api: :operations, recordable_type: "Page", operation: :show)
    destroy = RecordingStudioApi.lookup(api: :operations, recordable_type: "Page", operation: :destroy)

    assert_equal true, show.sensitive
    assert_equal true, destroy.sensitive
    assert_equal %i[operations], show.apis
    refute RecordingStudioApi.lookup(api: :public, recordable_type: "Page", operation: :show)
  end

  def test_operations_api_keeps_every_operation_sensitive_when_listing_destroy
    RecordingStudioApi.configuration.api(:operations)
    RecordingStudioApi.register_default_resource_actions!(api: :operations)
    RecordingStudioApi.register_recordable_type_api(
      "Page",
      api: :operations,
      operations: %i[index show destroy],
      serializer: Serializer,
      output_keys: %i[title],
      sensitive: %i[destroy]
    )

    show = RecordingStudioApi.lookup(api: :operations, recordable_type: "Page", operation: :show)
    destroy = RecordingStudioApi.lookup(api: :operations, recordable_type: "Page", operation: :destroy)

    assert_equal true, show.sensitive
    assert_equal true, destroy.sensitive
  end

  def test_unknown_sensitive_operation_raises_at_registration
    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      register_page(sensitive: %i[export])
    end

    assert_includes error.message, "Unknown API operations in sensitive"
    assert_includes error.message, "export"
  end

  def test_type_operation_lookup_returns_input_output_and_http_handler
    custom_destroy = ->(_context) { :custom }
    register_page(writable_attributes: %i[title])
    RecordingStudioApi.register_resource_handler("Page", :destroy, handler: custom_destroy)

    create = RecordingStudioApi.lookup(recordable_type: "Page", operation: :create)
    destroy = RecordingStudioApi.lookup(recordable_type: "Page", operation: :destroy)

    assert_equal custom_destroy, destroy.handler
    assert_equal(
      { title: { type: :string, required: false, allow_blank: true } },
      create.input_contract
    )
    assert_equal({}, destroy.input_contract)
    assert_equal "object", create.output_schema[:type]
    assert_equal %w[id type root_id created_at updated_at], create.output_schema[:required]
    assert create.output_schema[:properties].key?(:title)
  end

  def test_capability_action_defaults_and_explicit_flags
    RecordingStudioApi.register_capability_action(
      :publish,
      capability: :publishable,
      handler: PublishHandler,
      input_contract: {
        fields: {
          note: {
            type: :string,
            required: true,
            allow_blank: false,
            description: "Shown on the published page.",
            example: "Ready"
          }
        }
      },
      openapi: {
        responses: {
          "200" => {
            content: {
              "application/json" => {
                schema: { type: "object", properties: { published: { type: "boolean" } } }
              }
            }
          }
        }
      }
    )
    RecordingStudioApi.configuration.api(:operations)
    RecordingStudioApi.register_capability_action(
      :publish,
      api: :operations,
      capability: :publishable,
      handler: PublishHandler
    )
    RecordingStudioApi.register_capability_action(
      :audit,
      api: :operations,
      capability: :auditable,
      handler: ->(_context) { :audit },
      sensitive: false
    )
    RecordingStudioApi.register_capability_action(
      :secret_publish,
      capability: :publishable,
      handler: PublishHandler,
      sensitive: true
    )

    public_publish = RecordingStudioApi.lookup(api: :public, action: :publish)
    operations_publish = RecordingStudioApi.lookup(api: :operations, action: :publish)
    audit = RecordingStudioApi.lookup(api: :operations, action: :audit)
    secret = RecordingStudioApi.lookup(action: :secret_publish)

    assert_equal PublishHandler, public_publish.handler
    assert_equal false, public_publish.sensitive
    assert_equal %i[public operations], public_publish.apis
    assert_equal :string, public_publish.input_contract[:note][:type]
    assert_equal true, public_publish.input_contract[:note][:required]
    assert_equal false, public_publish.input_contract[:note][:allow_blank]
    assert_equal "Shown on the published page.", public_publish.input_contract[:note][:description]
    assert_equal "Ready", public_publish.input_contract[:note][:example]
    assert_equal({ type: "object", properties: { published: { type: "boolean" } } }, public_publish.output_schema)
    assert_equal true, operations_publish.sensitive
    assert_equal false, audit.sensitive
    assert_equal true, secret.sensitive
    assert_equal %i[public], secret.apis
  end

  def test_registered_endpoint_defaults_and_explicit_flags
    RecordingStudioApi.register_endpoint(
      :ping,
      http_verb: :get,
      path: "ping",
      handler: PingHandler,
      input_contract: {
        fields: {
          token: { type: :string, required: false }
        }
      }
    )
    RecordingStudioApi.register_endpoint(
      :ping,
      api: :operations,
      http_verb: :get,
      path: "ping",
      handler: OpsPingHandler
    )
    RecordingStudioApi.register_endpoint(
      :health,
      api: :operations,
      http_verb: :get,
      path: "health",
      handler: PingHandler,
      sensitive: false
    )
    RecordingStudioApi.register_endpoint(
      :secret_ping,
      http_verb: :get,
      path: "secret-ping",
      handler: PingHandler,
      sensitive: true
    )

    public_ping = RecordingStudioApi.lookup(api: :public, endpoint: :ping)
    operations_ping = RecordingStudioApi.lookup(api: :operations, endpoint: :ping)
    health = RecordingStudioApi.lookup(api: :operations, endpoint: :health)
    secret = RecordingStudioApi.lookup(endpoint: :secret_ping)

    assert_equal PingHandler, public_ping.handler
    assert_equal OpsPingHandler, operations_ping.handler
    assert_equal false, public_ping.sensitive
    assert_equal %i[public operations], public_ping.apis
    assert_equal({ token: { type: :string, required: false } }, public_ping.input_contract)
    assert_equal({ type: "object" }, public_ping.output_schema)
    assert_equal true, operations_ping.sensitive
    assert_equal false, health.sensitive
    assert_equal true, secret.sensitive
  end

  def test_merging_sensitive_operations_follows_explicit_set_rules
    register_page
    RecordingStudioApi.register_recordable_type_api("Page", sensitive: %i[destroy])

    assert_equal false, RecordingStudioApi.lookup(recordable_type: "Page", operation: :show).sensitive
    assert_equal true, RecordingStudioApi.lookup(recordable_type: "Page", operation: :destroy).sensitive

    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.register_recordable_type_api("Page", sensitive: %i[update])
    end
    assert_includes error.message, "Sensitive operations cannot be redefined"
  end

  def test_invalid_sensitive_flag_raises_at_registration
    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.register_capability_action(
        :publish,
        capability: :publishable,
        handler: PublishHandler,
        sensitive: "yes"
      )
    end
    assert_includes error.message, "sensitive must be true or false"

    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.register_endpoint(
        :ping,
        http_verb: :get,
        path: "ping",
        handler: PingHandler,
        sensitive: "yes"
      )
    end
    assert_includes error.message, "sensitive must be true or false"
  end

  def test_registration_as_json_omits_sensitive
    register_page(sensitive: %i[destroy])
    RecordingStudioApi.register_capability_action(
      :secret_publish,
      capability: :publishable,
      handler: PublishHandler,
      sensitive: true
    )
    RecordingStudioApi.register_endpoint(
      :secret_ping,
      http_verb: :get,
      path: "secret-ping",
      handler: PingHandler,
      sensitive: true
    )

    page = RecordingStudioApi.configuration.recordable_registry.fetch("Page")
    action = RecordingStudioApi.capability_action(:secret_publish)
    endpoint = RecordingStudioApi.registered_endpoint(:secret_ping)

    refute page.as_json.key?(:sensitive)
    refute action.as_json.key?(:sensitive)
    refute endpoint.as_json.key?(:sensitive)
    assert_equal %i[destroy], page.sensitive_operations
    assert_equal true, action.sensitive
    assert_equal true, endpoint.sensitive
  end

  def test_page_create_lookup_marks_title_required
    register_page(
      writable_attributes: %i[title],
      openapi: {
        details_schema: {
          type: "object",
          properties: { title: { type: "string" } },
          required: ["title"]
        }
      }
    )

    create = RecordingStudioApi.lookup(recordable_type: "Page", operation: :create)

    assert_equal true, create.input_contract[:title][:required]
  end

  def test_page_body_field_includes_enum_from_details_schema
    register_page(
      writable_attributes: %i[title body],
      openapi: {
        details_schema: {
          type: "object",
          properties: {
            title: { type: "string" },
            body: { type: "string", enum: %w[short long] }
          }
        }
      }
    )

    create = RecordingStudioApi.lookup(recordable_type: "Page", operation: :create)

    assert_equal %w[short long], create.input_contract[:body][:enum]
  end

  def test_page_items_field_includes_nested_object_shape
    register_page(
      writable_attributes: %i[items],
      openapi: {
        details_schema: {
          type: "object",
          properties: {
            items: {
              type: "object",
              properties: {
                heading: { type: "string" }
              }
            }
          }
        }
      }
    )

    create = RecordingStudioApi.lookup(recordable_type: "Page", operation: :create)

    assert_equal :hash, create.input_contract[:items][:type]
    assert_equal({ heading: { type: "string" } }, create.input_contract[:items][:properties])
  end

  def test_lookup_deep_dups_schema_and_contract
    register_page(writable_attributes: %i[title])
    first = RecordingStudioApi.lookup(recordable_type: "Page", operation: :create)
    second = RecordingStudioApi.lookup(recordable_type: "Page", operation: :create)
    catalog = RecordingStudioApi::Services::DocumentationCatalog.recording_schema("Page")

    first.input_contract[:title][:type] = :integer
    first.output_schema[:required] << "hijacked"

    assert_equal :string, second.input_contract[:title][:type]
    refute_includes catalog[:required], "hijacked"
  end

  def test_lookup_returns_nil_for_unknown_targets
    register_page(operations: %i[index show])

    assert_nil RecordingStudioApi.lookup(recordable_type: "Page", operation: :destroy)
    assert_nil RecordingStudioApi.lookup(action: :missing)
    assert_nil RecordingStudioApi.lookup(endpoint: :missing)
  end

  private

  def register_page(**)
    RecordingStudioApi.register_recordable_type_api(
      "Page",
      serializer: Serializer,
      output_keys: %i[title],
      **
    )
  end
end
