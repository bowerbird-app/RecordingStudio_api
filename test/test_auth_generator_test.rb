# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"
require "generators/recording_studio_api/scalar_docs/scalar_docs_generator"
require "generators/recording_studio_api/test_auth/test_auth_generator"

class TestAuthGeneratorTest < Minitest::Test
  def test_installs_api_scoped_test_auth_into_matching_scalar_docs
    with_temp_app do |destination_root|
      install_scalar(destination_root, "operations_api", mount_path: "/admin/operations-api/docs", api_surface: "operations")
      generator = build_generator(
        destination_root,
        ["operations_api"],
        mount_path: "/admin/operations-api/docs",
        api_surface: "operations"
      )

      generator.invoke_all

      scalar_controller = read(destination_root, "app/controllers/operations_api/scalar_docs_controller.rb")
      credentials_controller = read(destination_root, "app/controllers/operations_api/scalar_test_credentials_controller.rb")
      concern = read(destination_root, "app/controllers/concerns/operations_api/scalar_test_auth.rb")
      show_view = read(destination_root, "app/views/operations_api/scalar_docs/show.html.erb")
      routes = read(destination_root, "config/routes.rb")

      assert_includes scalar_controller, "include OperationsApi::ScalarTestAuth"
      assert_includes scalar_controller, "before_action :load_scalar_test_auth"
      assert_includes credentials_controller, "RecordingStudioApi::Services::IssueTestCredential.call"
      assert_includes credentials_controller, "RecordingStudioApi::Services::RevokeTestCredential.call"
      assert_includes concern, '"operations"'
      assert_includes concern, "RecordingStudioApi.api_recordable_types(api: scalar_test_auth_api)"
      assert_includes concern, "Rails.env.local?"
      assert_includes show_view, '<%= render "test_auth" %>'
      assert_includes routes, 'post "/admin/operations-api/docs/:version/test-credential"'
      assert_includes routes, "as: :operations_api_scalar_test_credential"

      assert_generated_files_compile(destination_root)
    end
  end

  def test_supports_a_custom_scalar_controller_namespace
    with_temp_app do |destination_root|
      options = {
        mount_path: "/developer/reference",
        controller: "developer_docs/reference",
        api_surface: "partner"
      }
      install_scalar(destination_root, "partner_docs", **options)

      build_generator(destination_root, ["partner_docs"], options).invoke_all

      assert File.exist?(File.join(destination_root, "app/controllers/developer_docs/scalar_test_credentials_controller.rb"))
      assert File.exist?(File.join(destination_root, "app/controllers/concerns/developer_docs/scalar_test_auth.rb"))
      assert_includes read(destination_root, "app/controllers/developer_docs/reference_controller.rb"),
                      "include DeveloperDocs::ScalarTestAuth"
    end
  end

  def test_is_idempotent_and_revoke_removes_only_test_auth
    with_temp_app do |destination_root|
      install_scalar(destination_root, "public_api")
      build_generator(destination_root, ["public_api"]).invoke_all
      build_generator(destination_root, ["public_api"]).invoke_all

      routes = read(destination_root, "config/routes.rb")
      assert_equal 1, routes.scan("# BEGIN RecordingStudioApi test auth routes: public_api").size

      revoke = build_generator(destination_root, ["public_api"])
      revoke.stub(:behavior, :revoke) { revoke.invoke_all }

      assert File.exist?(File.join(destination_root, "app/controllers/public_api/scalar_docs_controller.rb"))
      refute File.exist?(File.join(destination_root, "app/controllers/public_api/scalar_test_credentials_controller.rb"))
      refute File.exist?(File.join(destination_root, "app/controllers/concerns/public_api/scalar_test_auth.rb"))
      refute File.exist?(File.join(destination_root, "app/views/public_api/scalar_docs/_test_auth.html.erb"))
      refute_includes read(destination_root, "app/controllers/public_api/scalar_docs_controller.rb"), "BEGIN RecordingStudioApi test auth"
      refute_includes read(destination_root, "app/views/public_api/scalar_docs/show.html.erb"), "BEGIN RecordingStudioApi test auth"
      refute_includes read(destination_root, "config/routes.rb"), "BEGIN RecordingStudioApi test auth routes"
      assert_includes read(destination_root, "config/routes.rb"), "BEGIN RecordingStudioApi Scalar docs"
    end
  end

  def test_requires_the_matching_scalar_installation
    with_temp_app do |destination_root|
      generator = build_generator(destination_root, ["public_api"])

      error = assert_raises(Thor::Error) { generator.ensure_scalar_installation }

      assert_includes error.message, "install matching Scalar docs"
    end
  end

  def test_rejects_test_credential_route_collisions
    with_temp_app do |destination_root|
      install_scalar(destination_root, "public_api")
      routes_path = File.join(destination_root, "config/routes.rb")
      source = File.read(routes_path).sub(
        /\nend\s*\z/,
        "\npost \"/api-docs/:version/test-credential\", to: \"existing#create\"\nend\n"
      )
      File.write(routes_path, source)
      generator = build_generator(destination_root, ["public_api"])

      error = assert_raises(Thor::Error) { generator.check_for_route_collisions }

      assert_includes error.message, "route collision"
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

  def install_scalar(destination_root, name, **options)
    RecordingStudioApi::Generators::ScalarDocsGenerator.new(
      [name],
      options,
      destination_root: destination_root
    ).invoke_all
  end

  def build_generator(destination_root, arguments, options = {})
    RecordingStudioApi::Generators::TestAuthGenerator.new(
      arguments,
      options,
      destination_root: destination_root
    )
  end

  def read(destination_root, path)
    File.read(File.join(destination_root, path))
  end

  def assert_generated_files_compile(destination_root)
    Dir[File.join(destination_root, "app/controllers/**/*.rb")].each do |path|
      RubyVM::InstructionSequence.compile(File.read(path))
    end

    Dir[File.join(destination_root, "app/views/**/*.erb")].each do |path|
      source = ActionView::Template::Handlers::ERB.erb_implementation.new(File.read(path)).src
      RubyVM::InstructionSequence.compile(source)
    end
  end
end