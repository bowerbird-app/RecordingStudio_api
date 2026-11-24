# frozen_string_literal: true

require "test_helper"

class RecordableRegistrationTest < Minitest::Test
  Serializer = ->(*) { {} }
  Resolver = ->(*) {}

  def test_server_create_parent_requires_a_callable_parent_resolver
    missing = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi::RecordableRegistration.new(recordable_type: "Page", create_parent: :server)
    end
    assert_includes missing.message, "parent_resolver is required when create_parent is :server for Page"

    unused = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi::RecordableRegistration.new(recordable_type: "Page", parent_resolver: ->(*) {})
    end
    assert_includes unused.message, "parent_resolver is only used when create_parent is :server for Page"

    registration = RecordingStudioApi::RecordableRegistration.new(
      recordable_type: "Page",
      create_parent: :server,
      parent_resolver: ->(context) { context }
    )
    assert_equal :server, registration.create_parent
    assert registration.server_create_parent?
    refute RecordingStudioApi::RecordableRegistration.new(recordable_type: "Page").server_create_parent?
  end

  def test_normalizes_the_public_registration_contract
    registration = RecordingStudioApi::RecordableRegistration.new(
      recordable_type: "Page",
      serializer: Serializer,
      output_keys: %i[title body],
      fields: { cover_image_url: { resolver: Resolver, include: :request, authorize: Resolver, openapi: { type: "string" } } },
      relationships: {
        images: {
          source: :children, child_type: "RecordingStudioAttachable::Attachment", many: true,
          include: true, serializer: Serializer, output_keys: %i[name content_type], limit: 20,
          order: { created_at: :asc }, endpoints: %i[index show], authorize: Resolver,
          description: "Images attached to this page.", openapi: { type: "array" }
        }
      }
    )

    assert_equal Serializer, registration.serializer
    assert_equal %w[title body], registration.output_keys
    field = registration.fields.fetch("cover_image_url")
    assert_equal :request, field.include
    assert_equal Resolver, field.resolver
    relationship = registration.relationships.fetch("images")
    assert_equal "RecordingStudioAttachable::Attachment", relationship.child_type
    assert relationship.many
    assert_equal %w[name content_type], relationship.output_keys
    assert_equal({ "created_at" => :asc }, relationship.order)
    assert_equal %i[index show], relationship.endpoints
    assert_equal "Images attached to this page.", relationship.description
  end

  def test_field_defaults_to_not_included_and_definitions_are_immutable
    registration = RecordingStudioApi::RecordableRegistration.new(
      recordable_type: "Page",
      fields: { cover_image_url: { resolver: Resolver, openapi: { example: "cover.png" } } }
    )

    field = registration.fields.fetch("cover_image_url")
    assert_equal false, field.include
    assert_predicate registration.fields, :frozen?
    assert_predicate field, :frozen?
    assert_predicate field.openapi, :frozen?
    assert_raises(FrozenError) { field.openapi[:example] = "other.png" }
  end

  def test_relationship_definitions_and_nested_metadata_are_immutable
    registration = RecordingStudioApi::RecordableRegistration.new(
      recordable_type: "Page",
      relationships: {
        images: {
          source: :children, child_type: "Image", many: true, serializer: Serializer,
          output_keys: %i[name], limit: 10, order: { created_at: :desc }, endpoints: [:index],
          openapi: { examples: [{ name: "cover" }] }
        }
      }
    )

    relationship = registration.relationships.fetch("images")
    assert_predicate relationship, :frozen?
    assert_predicate relationship.output_keys, :frozen?
    assert_predicate relationship.order, :frozen?
    assert_predicate relationship.endpoints, :frozen?
    assert_predicate relationship.openapi, :frozen?
    assert_raises(FrozenError) { relationship.output_keys << "other" }
    assert_raises(FrozenError) { relationship.order["id"] = :asc }
    assert_raises(FrozenError) { relationship.endpoints << :show }
    assert_raises(FrozenError) { relationship.openapi[:examples] << { name: "other" } }
  end

  def test_top_level_serializer_and_output_keys_must_be_declared_together
    RecordingStudioApi::RecordableRegistration.new(recordable_type: "Page")

    assert_configuration_error("Serializer must respond") do
      RecordingStudioApi::RecordableRegistration.new(recordable_type: "Page", serializer: Object.new, output_keys: [:title])
    end
    assert_configuration_error("Output keys are required") do
      RecordingStudioApi::RecordableRegistration.new(recordable_type: "Page", serializer: Serializer)
    end
    assert_configuration_error("Serializer is required") do
      RecordingStudioApi::RecordableRegistration.new(recordable_type: "Page", output_keys: [:title])
    end
  end

  def test_rejects_invalid_field_configurations
    assert_configuration_error("resolver") do
      RecordingStudioApi::RecordableRegistration.new(recordable_type: "Page", fields: { cover: {} })
    end
    assert_configuration_error("include") do
      RecordingStudioApi::RecordableRegistration.new(recordable_type: "Page", fields: { cover: { resolver: Resolver, include: :always } })
    end
    assert_configuration_error("OpenAPI") do
      RecordingStudioApi::RecordableRegistration.new(recordable_type: "Page", fields: { cover: { resolver: Resolver, openapi: :string } })
    end
    assert_configuration_error("authorize") do
      RecordingStudioApi::RecordableRegistration.new(recordable_type: "Page", fields: { cover: { resolver: Resolver, authorize: :admin } })
    end
    assert_configuration_error("options are invalid") do
      RecordingStudioApi::RecordableRegistration.new(recordable_type: "Page", fields: { cover: { resolver: Resolver, method: :cover } })
    end
  end

  def test_rejects_invalid_relationship_source_and_shape
    base = { serializer: Serializer, output_keys: %i[name] }
    assert_configuration_error("source") { relationship(source: :association, **base) }
    assert_configuration_error("many must be boolean") { relationship(source: :children, child_type: "Image", many: nil, **base) }
    assert_configuration_error("requires child_type") { relationship(source: :children, many: false, **base) }
    assert_configuration_error("cannot specify resolver") { relationship(source: :children, child_type: "Image", many: false, resolver: Resolver, **base) }
    assert_configuration_error("requires resolver") { relationship(source: :custom, many: false, **base) }
    assert_configuration_error("requires resolver") { relationship(source: :custom, many: false, resolver: :owner, **base) }
    assert_configuration_error("cannot specify child_type") { relationship(source: :custom, child_type: "Image", many: false, resolver: Resolver, **base) }
    assert_configuration_error("serializer") { relationship(source: :custom, many: false, resolver: Resolver, output_keys: %i[name]) }
    assert_configuration_error("output_keys are required") { relationship(source: :custom, many: false, resolver: Resolver, serializer: Serializer) }
  end

  def test_rejects_invalid_many_limit_order_endpoints_and_legacy_options
    base = { source: :children, child_type: "Image", many: true, serializer: Serializer, output_keys: %i[name], limit: 1 }
    assert_configuration_error("limit") { relationship(**base, limit: 0) }
    assert_configuration_error("order direction") { relationship(**base, order: { created_at: :random }) }
    assert_configuration_error("limit") { relationship(source: :children, child_type: "Image", many: false, serializer: Serializer, output_keys: %i[name], limit: 1) }
    assert_configuration_error("endpoints require") { relationship(source: :custom, many: true, resolver: Resolver, serializer: Serializer, output_keys: %i[name], limit: 1, endpoints: [:index]) }
    assert_configuration_error("endpoints are invalid") { relationship(**base, endpoints: [:export]) }
    assert_configuration_error("authorize") { relationship(**base, authorize: :admin) }
    assert_configuration_error("description") { relationship(**base, description: :images) }
    assert_configuration_error("options are invalid") { relationship(**base, types: ["Image"]) }
    assert_configuration_error("options are invalid") { relationship(**base, unknown: true) }
    assert_configuration_error("order attribute is not supported") { relationship(**base, order: { title: :asc }) }
    assert_configuration_error("order attribute is not supported") { relationship(**base, order: { password_digest: :asc }) }
    assert_configuration_error("order is only valid") do
      relationship(source: :children, child_type: "Image", many: false, serializer: Serializer, output_keys: %i[name], order: {})
    end
    assert_configuration_error("limit is only valid") do
      relationship(source: :children, child_type: "Image", many: false, serializer: Serializer, output_keys: %i[name], limit: nil)
    end
    assert_configuration_error("endpoints require") do
      relationship(source: :children, child_type: "Image", many: false, serializer: Serializer, output_keys: %i[name], endpoints: [])
    end
    assert_configuration_error("endpoints require") do
      relationship(source: :custom, many: false, resolver: Resolver, serializer: Serializer, output_keys: %i[name], endpoints: [])
    end
    assert_configuration_error("endpoints require") do
      relationship(source: :custom, many: true, resolver: Resolver, serializer: Serializer, output_keys: %i[name], limit: 1, endpoints: [])
    end
  end

  def test_rejects_reserved_names_and_response_key_collisions
    RecordingStudioApi::RecordableRegistration::RESERVED_RESPONSE_KEYS.each do |reserved_key|
      assert_configuration_error("reserved") do
        RecordingStudioApi::RecordableRegistration.new(
          recordable_type: "Page", serializer: Serializer, output_keys: [reserved_key]
        )
      end
    end
    assert_configuration_error("reserved") do
      RecordingStudioApi::RecordableRegistration.new(recordable_type: "Page", fields: { _meta: { resolver: Resolver } })
    end
    assert_configuration_error("collide") do
      RecordingStudioApi::RecordableRegistration.new(
        recordable_type: "Page", serializer: Serializer, output_keys: [:title], fields: { title: { resolver: Resolver } }
      )
    end
    assert_configuration_error("collide") do
      RecordingStudioApi::RecordableRegistration.new(
        recordable_type: "Page", serializer: Serializer, output_keys: [:title], fields: { images: { resolver: Resolver } },
        relationships: { images: { source: :custom, many: false, resolver: Resolver, serializer: Serializer, output_keys: [:name] } }
      )
    end
  end

  def test_registry_composes_new_and_identical_definitions_only
    registry = RecordingStudioApi::RecordableRegistry.new
    field = { resolver: Resolver, include: true }
    registry.register("Page", fields: { cover: field }, writable_attributes: [:title])
    registry.register("Page", fields: { cover: field, summary: { resolver: Resolver } }, writable_attributes: [:summary])

    registration = registry.fetch("Page")
    assert_equal %w[cover summary], registration.fields.keys.sort
    assert_equal %w[summary title], registration.writable_attributes

    assert_raises(RecordingStudioApi::ConfigurationError) do
      registry.register("Page", fields: { cover: { resolver: ->(*) { "different" } } })
    end
  end

  def test_registry_rejects_incompatible_relationship_and_serializer_redefinitions
    registry = RecordingStudioApi::RecordableRegistry.new
    relationship_options = { source: :children, child_type: "Image", many: true, serializer: Serializer, output_keys: [:name], limit: 10 }
    registry.register("Page", serializer: Serializer, output_keys: [:title], relationships: { images: relationship_options })

    assert_raises(RecordingStudioApi::ConfigurationError) do
      registry.register("Page", relationships: { images: relationship_options.merge(limit: 20) })
    end
    assert_raises(RecordingStudioApi::ConfigurationError) do
      registry.register("Page", serializer: ->(*) { {} })
    end
  end

  def test_registry_rejects_conflicting_explicit_operations_and_capability_actions
    registry = RecordingStudioApi::RecordableRegistry.new
    registry.register("Page", operations: %i[index show], capability_actions: [:publish])

    assert_configuration_error("Operations cannot be redefined") do
      registry.register("Page", operations: [:index])
    end
    assert_configuration_error("Capability actions cannot be redefined") do
      registry.register("Page", capability_actions: [:archive])
    end

    registry.register("Page", auto_capability_actions: false)
    assert_configuration_error("Auto capability actions cannot be redefined") do
      registry.register("Page", auto_capability_actions: true)
    end
  end

  def test_default_order_accepts_a_column_or_a_callable_and_rejects_a_bad_option
    column = RecordingStudioApi::RecordableRegistration.new(
      recordable_type: "KitSection",
      default_order: { title: :asc }
    )
    assert_equal "title", column.default_order.column
    assert_equal "asc", column.default_order.direction
    assert column.default_order_supplied?

    callable = ->(relation) { relation }
    computed = RecordingStudioApi::RecordableRegistration.new(
      recordable_type: "KitSection",
      default_order: callable
    )
    assert_equal callable, computed.default_order.callable
    assert_predicate computed.default_order, :callable?

    assert_configuration_error("column and direction or a callable") do
      RecordingStudioApi::RecordableRegistration.new(recordable_type: "KitSection", default_order: "title")
    end
    assert_configuration_error("must name one column") do
      RecordingStudioApi::RecordableRegistration.new(recordable_type: "KitSection", default_order: { title: :asc, name: :asc })
    end
    assert_configuration_error("column is invalid") do
      RecordingStudioApi::RecordableRegistration.new(recordable_type: "KitSection", default_order: { "title name" => :asc })
    end
    assert_configuration_error("asc or desc") do
      RecordingStudioApi::RecordableRegistration.new(recordable_type: "KitSection", default_order: { title: :sideways })
    end
    assert_configuration_error("must take the scoped relation") do
      RecordingStudioApi::RecordableRegistration.new(recordable_type: "KitSection", default_order: -> {})
    end

    named = ->(relation, _direction) { relation }
    positioned = RecordingStudioApi::RecordableRegistration.new(
      recordable_type: "KitSection",
      default_order: { name: "position", order: named }
    )
    assert_equal "position", positioned.default_order.name
    assert_equal "asc", positioned.default_order.direction
    assert_equal named, positioned.default_order.callable
    assert_predicate positioned.default_order, :named?

    descending = RecordingStudioApi::RecordableRegistration.new(
      recordable_type: "KitSection",
      default_order: { name: "position", direction: :desc, order: named }
    )
    assert_equal "desc", descending.default_order.direction

    assert_configuration_error("name is invalid") do
      RecordingStudioApi::RecordableRegistration.new(
        recordable_type: "KitSection",
        default_order: { name: "section position", order: named }
      )
    end
    assert_configuration_error("default_order is reserved") do
      RecordingStudioApi::RecordableRegistration.new(
        recordable_type: "KitSection",
        default_order: { name: "default_order", order: named }
      )
    end
    assert_configuration_error("created_at is reserved") do
      RecordingStudioApi::RecordableRegistration.new(
        recordable_type: "KitSection",
        default_order: { name: "created_at", order: named }
      )
    end
    assert_configuration_error("asc or desc") do
      RecordingStudioApi::RecordableRegistration.new(
        recordable_type: "KitSection",
        default_order: { name: "position", direction: :sideways, order: named }
      )
    end
    assert_configuration_error("must pass a callable as order") do
      RecordingStudioApi::RecordableRegistration.new(
        recordable_type: "KitSection",
        default_order: { name: "position", order: "position" }
      )
    end
    assert_configuration_error("relation and a direction") do
      RecordingStudioApi::RecordableRegistration.new(
        recordable_type: "KitSection",
        default_order: { name: "position", order: ->(relation) { relation } }
      )
    end
    assert_configuration_error("relation and a direction") do
      RecordingStudioApi::RecordableRegistration.new(
        recordable_type: "KitSection",
        default_order: { name: "position", order: ->(relation, direction:) { [relation, direction] } }
      )
    end
    assert_configuration_error("only accepts name, order, and direction") do
      RecordingStudioApi::RecordableRegistration.new(
        recordable_type: "KitSection",
        default_order: { name: "position", order: named, extra: true }
      )
    end
    assert_configuration_error("already a sortable attribute") do
      RecordingStudioApi::RecordableRegistration.new(
        recordable_type: "KitSection",
        sortable_attributes: [:position],
        default_order: { name: "position", order: named }
      )
    end
  end

  def test_registry_keeps_an_omitted_default_order_and_replaces_it_on_reload
    registry = RecordingStudioApi::RecordableRegistry.new
    registry.register("KitSection", default_order: { title: :asc })
    registry.register("KitSection", sortable_attributes: [:title])

    kept = registry.fetch("KitSection")
    assert_equal "title", kept.default_order.column
    assert_equal ["title"], kept.sortable_attributes

    assert_configuration_error("Default order cannot be redefined") do
      registry.register("KitSection", default_order: { title: :desc })
    end

    registry.prepare_for_reload!
    registry.register("KitSection", default_order: { title: :desc })
    assert_equal "desc", registry.fetch("KitSection").default_order.direction
  end

  def test_auto_capability_actions_defaults_to_true_and_rejects_non_booleans
    registration = RecordingStudioApi::RecordableRegistration.new(recordable_type: "Page")

    assert_equal true, registration.auto_capability_actions
    refute registration.auto_capability_actions_supplied?

    opted_out = RecordingStudioApi::RecordableRegistration.new(recordable_type: "Page", auto_capability_actions: false)
    assert_equal false, opted_out.auto_capability_actions
    assert opted_out.auto_capability_actions_supplied?

    assert_configuration_error("auto_capability_actions must be true or false") do
      RecordingStudioApi::RecordableRegistration.new(recordable_type: "Page", auto_capability_actions: :nope)
    end
  end

  private

  def relationship(**options)
    RecordingStudioApi::RecordableRegistration.new(recordable_type: "Page", relationships: { images: options })
  end

  def assert_configuration_error(fragment, &)
    error = assert_raises(RecordingStudioApi::ConfigurationError, &)
    assert_includes error.message, fragment
  end
end
