# frozen_string_literal: true

require "test_helper"

class RecordableRegistrationTest < Minitest::Test
  def test_immutable_fields_must_be_writable
    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi::RecordableRegistration.new(
        recordable_type: "Page",
        immutable_fields: %i[external_key]
      ).validate!
    end

    assert_includes error.message, "Immutable fields must be writable attributes"
  end

  def test_immutable_relationships_must_be_registered
    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi::RecordableRegistration.new(
        recordable_type: "Page",
        immutable_relationships: %i[children]
      ).validate!
    end

    assert_includes error.message, "Immutable relationships are not registered"
  end

  def test_output_keys_and_fields_are_normalized
    registration = RecordingStudioApi::RecordableRegistration.new(
      recordable_type: "Workspace",
      output_keys: %i[name external_key],
      fields: {
        name: :name,
        external_key: { source: :external_key, type: :string }
      }
    )

    assert registration.validate!
    assert_equal(
      %w[name external_key],
      registration.output_keys
    )
    assert_equal :name, registration.fields.fetch("name")
    assert_equal :external_key, registration.fields.fetch("external_key").fetch(:source)
  end

  def test_named_relationships_support_children_and_custom_sources
    registration = RecordingStudioApi::RecordableRegistration.new(
      recordable_type: "Workspace",
      relationships: {
        folders: { source: :children, types: ["Folder"], include: :request },
        owner: {
          source: :custom,
          include: true,
          resolver: ->(_workspace) { nil },
          output_keys: %i[name],
          fields: { name: :name }
        }
      }
    )

    assert registration.validate!
    assert_equal :children, registration.relationships.fetch("folders").fetch(:source)
    assert_equal :request, registration.relationships.fetch("folders").fetch(:include)
    assert_equal :custom, registration.relationships.fetch("owner").fetch(:source)
    assert_equal true, registration.relationships.fetch("owner").fetch(:include)
  end

  def test_relationships_require_a_supported_source
    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi::RecordableRegistration.new(
        recordable_type: "Workspace",
        relationships: { folders: { source: :association } }
      )
    end

    assert_includes error.message, "source must be one of: children, custom"
  end

  def test_relationship_registration_cannot_reenable_a_restricted_named_edge
    registry = RecordingStudioApi::RecordableRegistry.new
    registry.register("Workspace", relationships: { folders: { source: :children, read: true, write: false } })
    registry.register("Workspace", relationships: { folders: { source: :children, types: ["Folder"] } })

    relationship = registry.fetch("Workspace").relationships.fetch("folders")
    assert_equal ["Folder"], relationship.fetch(:types)
    assert_equal true, relationship.fetch(:read)
    assert_equal false, relationship.fetch(:write)
  end

  def test_relationships_are_read_only_by_default
    relationship = RecordingStudioApi::RecordableRegistration.new(
      recordable_type: "Workspace",
      relationships: { folders: { source: :children } }
    ).relationships.fetch("folders")

    assert_equal false, relationship.fetch(:write)
  end

  def test_relationship_names_cannot_override_canonical_response_keys
    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi::RecordableRegistration.new(
        recordable_type: "Workspace",
        relationships: { id: { source: :children } }
      )
    end

    assert_includes error.message, "Relationship name is reserved"
  end
end
