# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"
require "generators/recording_studio_api/scalar_docs/scalar_docs_generator"

class ScalarDocsGeneratorTest < Minitest::Test
  def test_generator_installs_gem_owned_routes_and_explicit_access_configuration
    with_temp_app do |destination_root|
      build_generator(destination_root, ["public_api"]).invoke_all

      routes = File.read(File.join(destination_root, "config/routes.rb"))
      initializer = File.read(File.join(destination_root, "config/initializers/recording_studio_api_scalar_docs_public_api.rb"))

      assert_includes routes, "recording_studio_api_scalar_docs_for :public"
      assert_includes routes, 'at: "/api-docs"'
      assert_includes routes, "as: :public_api_scalar_docs"
      assert_includes routes, 'engine_mount_path: "/recording_studio_api"'
      assert_includes initializer, "api.documentation_enabled = true"
      assert_includes initializer, "api.documentation_access = :authenticated"
      refute File.exist?(File.join(destination_root, "app/controllers/public_api/scalar_docs_controller.rb"))
      refute File.exist?(File.join(destination_root, "app/views/public_api/scalar_docs"))

      RubyVM::InstructionSequence.compile(initializer)
    end
  end

  def test_generator_supports_named_api_public_access_custom_mount_and_layout
    with_temp_app do |destination_root|
      build_generator(
        destination_root,
        ["operations_api"],
        mount_path: "/admin/operations-api/docs",
        api_mount_path: "/gateway/api",
        api_surface: "operations",
        access: "public",
        layout: "portal"
      ).invoke_all

      routes = File.read(File.join(destination_root, "config/routes.rb"))
      initializer = File.read(File.join(destination_root, "config/initializers/recording_studio_api_scalar_docs_operations_api.rb"))

      assert_includes routes, "recording_studio_api_scalar_docs_for :operations"
      assert_includes routes, 'at: "/admin/operations-api/docs"'
      assert_includes routes, 'engine_mount_path: "/gateway/api"'
      assert_includes initializer, "api = config.api(:operations)"
      assert_includes initializer, "api.documentation_access = :public"
      assert_includes initializer, 'api.documentation_layout_name = "portal"'
    end
  end

  def test_generator_is_idempotent_and_revoke_removes_only_managed_artifacts
    with_temp_app do |destination_root|
      legacy_controller = File.join(destination_root, "app/controllers/public_api/scalar_docs_controller.rb")
      FileUtils.mkdir_p(File.dirname(legacy_controller))
      File.write(legacy_controller, "class PublicApi::ScalarDocsController; end\n")

      build_generator(destination_root, ["public_api"]).invoke_all
      build_generator(destination_root, ["public_api"]).invoke_all

      routes = File.read(File.join(destination_root, "config/routes.rb"))
      assert_equal 1, routes.scan("# BEGIN RecordingStudioApi Scalar docs: public_api").size

      revoke = build_generator(destination_root, ["public_api"])
      revoke.stub(:behavior, :revoke) { revoke.invoke_all }

      refute_includes File.read(File.join(destination_root, "config/routes.rb")), "RecordingStudioApi Scalar docs: public_api"
      refute File.exist?(File.join(destination_root, "config/initializers/recording_studio_api_scalar_docs_public_api.rb"))
      assert File.exist?(legacy_controller)
    end
  end

  def test_generator_rejects_invalid_options_and_route_collisions
    with_temp_app do |destination_root|
      invalid = build_generator(destination_root, ["../unsafe"], access: "everyone")
      error = assert_raises(Thor::Error) { invalid.validate_configuration }
      assert_includes error.message, "NAME"
      assert_includes error.message, "--access"

      File.write(
        File.join(destination_root, "config/routes.rb"),
        "Rails.application.routes.draw do\n  get \"/existing\", as: :public_api_scalar_docs\nend\n"
      )
      generator = build_generator(destination_root, ["public_api"])

      error = assert_raises(Thor::Error) { generator.check_for_route_collisions }
      assert_includes error.message, "route collision"
    end
  end

  def test_generator_rejects_dynamic_mount_paths
    with_temp_app do |destination_root|
      generator = build_generator(destination_root, ["public_api"], mount_path: "/api-docs/:tenant")

      error = assert_raises(Thor::Error) { generator.validate_configuration }

      assert_includes error.message, "--mount-path"
    end
  end

  private

  def with_temp_app
    Dir.mktmpdir do |directory|
      FileUtils.mkdir_p(File.join(directory, "config/initializers"))
      File.write(File.join(directory, "config/routes.rb"), "Rails.application.routes.draw do\nend\n")
      yield directory
    end
  end

  def build_generator(destination_root, arguments, options = {})
    RecordingStudioApi::Generators::ScalarDocsGenerator.new(
      arguments,
      options,
      destination_root: destination_root
    )
  end
end
