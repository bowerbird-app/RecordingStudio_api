# frozen_string_literal: true

require "test_helper"
require "erb"
require "fileutils"
require "tmpdir"
require "generators/recording_studio_api/scalar_docs/scalar_docs_generator"

class ScalarDocsGeneratorTest < Minitest::Test
  def test_generator_creates_namespaced_controller_views_and_ordered_routes
    with_temp_app do |destination_root|
      generator = build_generator(destination_root, ["public_api"])

      generator.invoke_all

      controller = File.read(File.join(destination_root, "app/controllers/public_api/scalar_docs_controller.rb"))
      routes = File.read(File.join(destination_root, "config/routes.rb"))

      assert_includes controller, "module PublicApi"
      assert_includes controller, "class ScalarDocsController < ApplicationController"
      assert_includes controller, "Unsupported API version"
      assert_includes controller, "authorize_scalar_documentation!"
      assert_includes controller, "mount_path: \"/recording_studio_api\""
      assert_includes controller, "api_mount_path: \"/api\""

      assert_includes routes, "# BEGIN RecordingStudioApi Scalar docs: public_api"
      assert_includes routes, "as: :public_api_scalar_docs"
      assert_operator routes.index("/:version/openapi.json"), :<, routes.index("/:version/fullscreen")
      assert_operator routes.index("/:version/fullscreen"), :<, routes.index('"/api-docs/:version"')

      assert_framework_agnostic_views(destination_root)
      assert_generated_ruby_and_erb_compile(destination_root)
    end
  end

  def test_generator_is_idempotent_and_revoke_removes_marked_route_block
    with_temp_app do |destination_root|
      generator = build_generator(destination_root, ["public_api"])
      generator.invoke_all

      generator = build_generator(destination_root, ["public_api"])
      generator.invoke_all

      routes = File.read(File.join(destination_root, "config/routes.rb"))
      assert_equal 1, routes.scan("# BEGIN RecordingStudioApi Scalar docs: public_api").size

      generator = build_generator(destination_root, ["public_api"])
      generator.stub(:behavior, :revoke) { generator.invoke_all }

      refute_includes File.read(File.join(destination_root, "config/routes.rb")), "# BEGIN RecordingStudioApi Scalar docs: public_api"
      refute File.exist?(File.join(destination_root, "app/controllers/public_api/scalar_docs_controller.rb"))
    end
  end

  def test_generator_rejects_invalid_options_and_route_helper_collisions
    with_temp_app do |destination_root|
      invalid = build_generator(destination_root, ["../unsafe"])
      error = assert_raises(Thor::Error) { invalid.validate_configuration }
      assert_includes error.message, "Scalar documentation generator failed"

      invalid_integrity = build_generator(destination_root, ["public_api"], scalar_integrity: "sha1-not-supported")
      error = assert_raises(Thor::Error) { invalid_integrity.validate_configuration }
      assert_includes error.message, "--scalar-integrity"

      File.write(
        File.join(destination_root, "config/routes.rb"),
        "Rails.application.routes.draw do\n  get \"/existing\", as: :public_api_scalar_docs\nend\n"
      )
      generator = build_generator(destination_root, ["public_api"])

      error = assert_raises(Thor::Error) { generator.check_for_route_collisions }
      assert_includes error.message, "route collision"
    end
  end

  def test_generator_rejects_dynamic_route_syntax_in_mount_paths
    with_temp_app do |destination_root|
      {
        mount_path: ["/api-docs(optional)", "/api-docs/*rest", "/api-docs/:tenant"],
        api_mount_path: ["/recording_studio_api(optional)", "/recording_studio_api/*rest", "/recording_studio_api/:tenant"]
      }.each do |option, invalid_paths|
        invalid_paths.each do |invalid_path|
          generator = build_generator(destination_root, ["public_api"], option => invalid_path)

          error = assert_raises(Thor::Error) { generator.validate_configuration }

          assert_includes error.message, "--#{option.to_s.tr('_', '-')}"
        end
      end
    end
  end

  def test_generator_accepts_literal_safe_mount_path_punctuation
    with_temp_app do |destination_root|
      generator = build_generator(
        destination_root,
        ["public_api"],
        mount_path: "/developer/reference-v2_1.0~beta",
        api_mount_path: "/gateway/recording-api_v2.1~beta"
      )

      generator.validate_configuration
    end
  end

  def test_generator_rejects_http_urls_without_a_host
    with_temp_app do |destination_root|
      invalid_source = build_generator(destination_root, ["public_api"], scalar_source: "https://")
      error = assert_raises(Thor::Error) { invalid_source.validate_configuration }
      assert_includes error.message, "--scalar-source"

      invalid_scalar_url = build_generator(destination_root, ["public_api"], scalar_url: "http://")
      error = assert_raises(Thor::Error) { invalid_scalar_url.validate_configuration }
      assert_includes error.message, "--scalar-url"
    end
  end

  def test_generator_detects_parenthesized_and_non_get_route_path_collisions
    with_temp_app do |destination_root|
      File.write(
        File.join(destination_root, "config/routes.rb"),
        <<~RUBY
          Rails.application.routes.draw do
            get("/api-docs", to: "existing#show")
            match "/api-docs/:version/openapi.json", to: "existing#show", via: :get
            post("/api-docs/:version/fullscreen", to: "existing#create")
            delete "/api-docs/:version", to: "existing#destroy"
          end
        RUBY
      )
      generator = build_generator(destination_root, ["public_api"])

      error = assert_raises(Thor::Error) { generator.check_for_route_collisions }

      assert_includes error.message, "/api-docs"
      assert_includes error.message, "/api-docs/:version/openapi.json"
      assert_includes error.message, "/api-docs/:version/fullscreen"
      assert_includes error.message, "/api-docs/:version"
    end
  end

  def test_generator_honors_custom_provider_urls_and_mount_context
    with_temp_app do |destination_root|
      generator = build_generator(
        destination_root,
        ["partner_docs"],
        mount_path: "/developer/reference",
        api_mount_path: "/gateway/api",
        controller: "developer_docs/reference",
        layout: "portal",
        scalar_source: "https://cdn.example.test/scalar.js",
        scalar_integrity: "sha384-AbCdEf123+/=",
        scalar_url: "https://docs.example.test/openapi.json",
        default_api_version: "v2",
        openapi_provider: "Partner::OpenapiProvider"
      )

      generator.invoke_all

      controller = File.read(File.join(destination_root, "app/controllers/developer_docs/reference_controller.rb"))
      routes = File.read(File.join(destination_root, "config/routes.rb"))
      scalar_view = File.read(File.join(destination_root, "app/views/developer_docs/reference/_scalar.html.erb"))

      assert_includes controller, "layout \"portal\""
      assert_includes controller, "Partner::OpenapiProvider"
      assert_includes controller, "mount_path: \"/gateway/api\""
      assert_includes controller, "https://docs.example.test/openapi.json"
      assert_includes controller, "sha384-AbCdEf123+/="
      assert_includes routes, "redirect(\"/developer/reference/v2\")"
      assert_includes scalar_view, "https://cdn.example.test/scalar.js"
      assert_includes scalar_view, 'crossorigin="anonymous"'
      assert_includes scalar_view, "function scalarTarget()"
      assert_includes scalar_view, "displayScalarLoadFailure()"
    end
  end

  def test_generator_only_uses_source_matched_or_explicit_integrity
    with_temp_app do |destination_root|
      default_generator = build_generator(destination_root, ["default_docs"])
      custom_generator = build_generator(
        destination_root,
        ["custom_docs"],
        scalar_source: "https://cdn.example.test/scalar.js"
      )
      explicit_generator = build_generator(
        destination_root,
        ["explicit_docs"],
        scalar_source: "https://cdn.example.test/scalar.js",
        scalar_integrity: "sha384-AbCdEf123+/="
      )

      assert_nil default_generator.send(:scalar_integrity)
      assert_nil custom_generator.send(:scalar_integrity)
      assert_equal "sha384-AbCdEf123+/=", explicit_generator.send(:scalar_integrity)
    end
  end

  def test_revoke_removes_named_route_block_despite_changed_mount_options
    with_temp_app do |destination_root|
      original = build_generator(
        destination_root,
        ["partner_docs"],
        mount_path: "/developer/reference",
        controller: "developer_docs/reference"
      )
      original.invoke_all

      custom_controller = File.join(destination_root, "app/controllers/developer_docs/reference_controller.rb")
      assert File.exist?(custom_controller)

      pretend_revoke = build_generator(destination_root, ["partner_docs"], mount_path: "/different", pretend: true)
      pretend_revoke.stub(:behavior, :revoke) { pretend_revoke.add_routes }
      assert_includes File.read(File.join(destination_root, "config/routes.rb")),
                      "# BEGIN RecordingStudioApi Scalar docs: partner_docs"

      revoke = build_generator(destination_root, ["partner_docs"], mount_path: "/different")
      revoke.stub(:behavior, :revoke) { revoke.invoke_all }

      routes = File.read(File.join(destination_root, "config/routes.rb"))
      refute_includes routes, "# BEGIN RecordingStudioApi Scalar docs: partner_docs"
      assert File.exist?(custom_controller), "custom controller requires the same --controller option during revoke"

      revoke = build_generator(
        destination_root,
        ["partner_docs"],
        controller: "developer_docs/reference"
      )
      revoke.stub(:behavior, :revoke) { revoke.invoke_all }

      refute File.exist?(custom_controller)
    end
  end

  private

  def with_temp_app
    Dir.mktmpdir do |directory|
      FileUtils.mkdir_p(File.join(directory, "config"))
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

  def assert_framework_agnostic_views(destination_root)
    views = Dir[File.join(destination_root, "app/views/public_api/scalar_docs/*.erb")]
    contents = views.map { |path| File.read(path) }.join

    refute_includes contents, "FlatPack"
    refute_includes contents, "tailwind"
    refute_includes contents, "dummy"
  end

  def assert_generated_ruby_and_erb_compile(destination_root)
    controller = File.read(File.join(destination_root, "app/controllers/public_api/scalar_docs_controller.rb"))
    RubyVM::InstructionSequence.compile(controller)

    Dir[File.join(destination_root, "app/views/public_api/scalar_docs/*.erb")].each do |path|
      RubyVM::InstructionSequence.compile(ERB.new(File.read(path)).src)
    end
  end
end
