# frozen_string_literal: true

require "test_helper"

class RecordablePublicNameTest < Minitest::Test
  def test_public_name_falls_back_to_the_class_name_without_its_namespace
    registration = RecordingStudioApi::RecordableRegistration.new(
      recordable_type: "RecordingStudioPresskits::PressKit"
    )
    blank = RecordingStudioApi::RecordableRegistration.new(
      recordable_type: "RecordingStudioPresskits::PressKit",
      public_name: "  "
    )

    assert_equal "PressKit", registration.public_name
    assert_equal "PressKit", blank.public_name
  end

  def test_explicit_public_name_is_stored_as_a_string
    with_configuration do
      RecordingStudioApi.register_recordable_type_api(
        "RecordingStudioPresskits::PressKit",
        public_name: :Kit
      )
      RecordingStudioApi.register_recordable_type_api(
        "RecordingStudioPresskits::PressKit",
        openapi: { tags: ["Press"] }
      )

      registration = RecordingStudioApi.recordable_registration_for("RecordingStudioPresskits::PressKit")

      assert_equal "Kit", registration.public_name
      assert_equal ["Press"], registration.openapi.fetch(:tags)

      error = assert_raises(RecordingStudioApi::ConfigurationError) do
        RecordingStudioApi.register_recordable_type_api(
          "RecordingStudioPresskits::PressKit",
          public_name: "Other"
        )
      end
      assert_equal "Public name cannot be redefined incompatibly for RecordingStudioPresskits::PressKit", error.message
    end
  end

  def test_public_name_rejects_an_identifier_with_spaces
    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi::RecordableRegistration.new(
        recordable_type: "RecordingStudioPresskits::PressKit",
        public_name: "Press Kit"
      )
    end

    assert_equal "Public name is invalid for RecordingStudioPresskits::PressKit: Press Kit", error.message
  end

  def test_public_name_clash_inside_one_named_api_names_both_classes
    with_configuration do |configuration|
      configuration.recordable_registry.register("AddonA::Video")
      configuration.recordable_registry.register("AddonB::Video")

      error = assert_raises(RecordingStudioApi::ConfigurationError) { configuration.validate! }

      assert_includes error.message, "Public name Video clashes for AddonA::Video, AddonB::Video"
    end
  end

  def test_the_same_public_name_is_allowed_on_two_named_apis
    with_configuration do |configuration|
      configuration.api(:operations)
      RecordingStudioApi.register_recordable_type_api("AddonA::Video")
      RecordingStudioApi.register_recordable_type_api("AddonB::Video", api: :operations)

      configuration.validate!

      assert_equal "AddonA::Video", RecordingStudioApi.recordable_type_for_public_name("Video")
      assert_equal "AddonB::Video", RecordingStudioApi.recordable_type_for_public_name("Video", api: :operations)
      assert_nil RecordingStudioApi.recordable_type_for_public_name("Missing")
      assert_nil RecordingStudioApi.recordable_type_for_public_name("Missing", api: :operations)
      assert_nil RecordingStudioApi.recordable_type_for_public_name("AddonA::Video", api: :operations)
    end
  end

  def test_full_class_name_still_resolves
    with_configuration do
      RecordingStudioApi.register_recordable_type_api(
        "RecordingStudioPresskits::PressKit",
        public_name: "Kit"
      )

      registration = RecordingStudioApi.recordable_registration_for("RecordingStudioPresskits::PressKit")

      assert_equal "Kit", registration.public_name
      assert_equal "RecordingStudioPresskits::PressKit", registration.recordable_type
      assert_equal "RecordingStudioPresskits::PressKit", RecordingStudioApi.recordable_type_for_public_name("Kit")
      assert_equal(
        "RecordingStudioPresskits::PressKit",
        RecordingStudioApi.recordable_type_for_public_name("RecordingStudioPresskits::PressKit")
      )
    end
  end

  private

  def with_configuration
    defined = RecordingStudioApi.instance_variable_defined?(:@configuration)
    original = RecordingStudioApi.instance_variable_get(:@configuration)
    configuration = RecordingStudioApi::Configuration.new
    RecordingStudioApi.instance_variable_set(:@configuration, configuration)
    yield configuration
  ensure
    if defined
      RecordingStudioApi.instance_variable_set(:@configuration, original)
    elsif RecordingStudioApi.instance_variable_defined?(:@configuration)
      RecordingStudioApi.remove_instance_variable(:@configuration)
    end
  end
end
