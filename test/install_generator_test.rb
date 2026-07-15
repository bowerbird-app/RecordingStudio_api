# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"
require "generators/recording_studio_api/install/install_generator"
require "generators/recording_studio_api/migrations/migrations_generator"
require "generators/recording_studio_api/admin_screens/admin_screens_generator"

class InstallGeneratorTest < Minitest::Test
  INSTALL_TEMPLATE_PATH = File.expand_path(
    "../lib/generators/recording_studio_api/install/templates/INSTALL.md",
    __dir__
  )

  def with_temp_app
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "app/assets/tailwind"))
      yield dir
    end
  end

  def build_generator(destination_root, options = {})
    RecordingStudioApi::Generators::InstallGenerator.new(
      [],
      options,
      destination_root: destination_root
    )
  end

  def build_admin_screens_generator(destination_root, options = {})
    RecordingStudioApi::Generators::AdminScreensGenerator.new(
      [],
      options,
      destination_root: destination_root
    )
  end

  def test_mount_engine_uses_configured_mount_path
    generator = build_generator("/tmp", mount_path: "/addons/recording")
    routes = []

    generator.stub(:route, ->(value) { routes << value }) do
      generator.mount_engine
    end

    assert_equal ["mount RecordingStudioApi::Engine, at: \"/addons/recording\""], routes
  end

  def test_add_tailwind_source_injects_engine_and_flatpack_sources
    with_temp_app do |dir|
      css_path = File.join(dir, "app/assets/tailwind/application.css")
      File.write(css_path, "@import \"tailwindcss\";\n")

      generator = build_generator(dir)

      Rails.stub(:root, Pathname.new(dir)) do
        generator.stub(:say, nil) do
          generator.add_tailwind_source
        end
      end

      css = File.read(css_path)
      assert_tailwind_sources_present(css)
    end
  end

  def test_add_tailwind_source_does_not_duplicate_existing_entries
    with_temp_app do |dir|
      css_path = File.join(dir, "app/assets/tailwind/application.css")
      File.write(css_path, <<~CSS)
        @import "tailwindcss";
        @source "../../vendor/bundle/**/recording_studio_api/app/views/**/*.erb";
        @source "../../../../../../usr/local/bundle/ruby/**/bundler/gems/recording_studio_api-*/app/views/**/*.erb";
        @source "../../vendor/bundle/**/flatpack/app/components/**/*.{rb,erb}";
        @source "../../../../../../usr/local/bundle/ruby/**/bundler/gems/flatpack-*/app/components/**/*.{rb,erb}";
      CSS

      generator = build_generator(dir)

      Rails.stub(:root, Pathname.new(dir)) do
        generator.stub(:say, nil) do
          generator.add_tailwind_source
        end
      end

      css = File.read(css_path)
      assert_tailwind_sources_present(css)
      assert_tailwind_sources_count(css, 1)
    end
  end

  def test_add_tailwind_source_reports_missing_tailwind_config
    with_temp_app do |dir|
      FileUtils.rm_rf(File.join(dir, "app/assets/tailwind"))
      generator = build_generator(dir)
      messages = []

      Rails.stub(:root, Pathname.new(dir)) do
        generator.stub(:say, ->(message, color = nil) { messages << [message, color] }) do
          generator.add_tailwind_source
        end
      end

      assert_includes messages, ["Tailwind CSS not detected. Skipping Tailwind configuration.", :yellow]
      assert_includes messages, ["If you use Tailwind, add these lines to your Tailwind CSS config:", :yellow]
      tailwind_source_lines.each do |line|
        assert_includes messages, ["  #{line}", :yellow]
      end
    end
  end

  def test_add_tailwind_source_reports_manual_configuration_when_import_is_missing
    with_temp_app do |dir|
      css_path = File.join(dir, "app/assets/tailwind/application.css")
      File.write(css_path, "@source \"../local/**/*.erb\";\n")
      generator = build_generator(dir)
      messages = []

      Rails.stub(:root, Pathname.new(dir)) do
        generator.stub(:say, ->(message, color = nil) { messages << [message, color] }) do
          generator.add_tailwind_source
        end
      end

      assert_equal "@source \"../local/**/*.erb\";\n", File.read(css_path)
      assert_includes messages, ["Could not find @import \"tailwindcss\" in your Tailwind config.", :yellow]
      assert_includes messages, ["Please manually add these lines to your Tailwind CSS config:", :yellow]
      tailwind_source_lines.each do |line|
        assert_includes messages, ["  #{line}", :yellow]
      end
    end
  end

  def test_show_readme_displays_install_guide_for_invoke_behavior
    generator = build_generator("/tmp")
    shown_templates = []

    generator.stub(:behavior, :invoke) do
      generator.stub(:readme, ->(template) { shown_templates << template }) do
        generator.show_readme
      end
    end

    assert_equal ["INSTALL.md"], shown_templates
  end

  def test_migrations_generator_exists_under_renamed_namespace
    generator_path = File.expand_path("../lib/generators/recording_studio_api/migrations/migrations_generator.rb",
                                      __dir__)

    assert File.exist?(generator_path)
    assert_equal RecordingStudioApi::Generators::MigrationsGenerator, RecordingStudioApi::Generators::MigrationsGenerator
  end

  def test_admin_screens_generator_adds_api_route
    generator = build_admin_screens_generator("/tmp", api_mount_path: "/api")
    routes = []

    generator.stub(:route, ->(value) { routes << value }) do
      generator.add_api_route
    end

    assert_equal ['recording_studio_admin_for :api, at: "/api", root_section: :api'], routes
  end

  def test_admin_screens_generator_wires_user_api_sections
    with_temp_app do |destination_root|
      FileUtils.mkdir_p(File.join(destination_root, "app/models"))
      File.write(File.join(destination_root, "app/models/workspace.rb"), <<~RUBY)
        class Workspace < ApplicationRecord
          recording_studio_recordable label: "Workspace", root: true
        end
      RUBY

      generator = build_admin_screens_generator(
        destination_root,
        user_roots: ["Workspace"]
      )

      generator.stub(:say, nil) do
        generator.add_user_api_sections
      end

      workspace_source = File.read(File.join(destination_root, "app/models/workspace.rb"))
      assert_includes workspace_source, "include RecordingStudioAdmin::AllowsAdminSections"
      assert_includes workspace_source, "recording_studio_admin_sections do"
      assert_includes workspace_source, "section :api"
    end
  end

  def test_migrations_generator_reports_when_source_directory_is_missing
    with_temp_app do |destination_root|
      source_root = Dir.mktmpdir
      generator = RecordingStudioApi::Generators::MigrationsGenerator.new([], {}, destination_root: destination_root)
      messages = []

      RecordingStudioApi::Generators::MigrationsGenerator.stub(:source_root, source_root) do
        generator.stub(:say, ->(message, color = nil) { messages << [message, color] }) do
          generator.copy_migrations
        end
      end

      assert_includes messages, ["No migrations found in RecordingStudioApi engine.", :yellow]
    ensure
      FileUtils.remove_entry(source_root)
    end
  end

  def test_migrations_generator_reports_when_no_migration_files_exist
    with_temp_app do |destination_root|
      source_root = Dir.mktmpdir
      FileUtils.mkdir_p(File.join(source_root, "db/migrate"))
      generator = RecordingStudioApi::Generators::MigrationsGenerator.new([], {}, destination_root: destination_root)
      messages = []

      RecordingStudioApi::Generators::MigrationsGenerator.stub(:source_root, source_root) do
        generator.stub(:say, ->(message, color = nil) { messages << [message, color] }) do
          generator.copy_migrations
        end
      end

      assert_includes messages, ["No migrations found in RecordingStudioApi engine.", :yellow]
    ensure
      FileUtils.remove_entry(source_root)
    end
  end

  def test_migrations_generator_skips_existing_and_copies_new_migrations
    with_temp_app do |destination_root|
      source_root = Dir.mktmpdir
      source_migrations_dir = File.join(source_root, "db/migrate")
      destination_migrations_dir = File.join(destination_root, "db/migrate")

      FileUtils.mkdir_p(source_migrations_dir)
      FileUtils.mkdir_p(destination_migrations_dir)

      existing_name = "create_recording_studio_api_existing.rb"
      new_name = "create_recording_studio_api_new_table.rb"
      File.write(File.join(source_migrations_dir, "20250101000001_#{existing_name}"), "# existing")
      File.write(File.join(source_migrations_dir, "20250101000002_#{new_name}"), "# new")
      File.write(File.join(destination_migrations_dir, "20260101000001_#{existing_name}"), "# already installed")

      generator = RecordingStudioApi::Generators::MigrationsGenerator.new([], { skip_existing: true }, destination_root: destination_root)
      copied = []
      messages = []
      sequence = Enumerator.new do |y|
        y << "20270101000001"
        y << "20270101000002"
      end

      RecordingStudioApi::Generators::MigrationsGenerator.stub(:source_root, source_root) do
        generator.stub(:next_migration_number, -> { sequence.next }) do
          generator.stub(:copy_file, ->(source, destination) { copied << [source, destination] }) do
            generator.stub(:sleep, nil) do
              generator.stub(:say, ->(message, color = nil) { messages << [message, color] }) do
                generator.copy_migrations
              end
            end
          end
        end
      end

      assert_equal 1, copied.size
      assert copied.first.last.end_with?("_#{new_name}")
      assert_includes messages, ["  skip  #{existing_name} (already exists)", :yellow]
    ensure
      FileUtils.remove_entry(source_root)
    end
  end

  def test_migration_exists_and_next_migration_number_helpers
    with_temp_app do |destination_root|
      migrations_dir = File.join(destination_root, "db/migrate")
      FileUtils.mkdir_p(migrations_dir)
      migration_name = "create_recording_studio_api_table.rb"
      File.write(File.join(migrations_dir, "20260101000000_#{migration_name}"), "# migration")

      generator = RecordingStudioApi::Generators::MigrationsGenerator.new([], {}, destination_root: destination_root)

      assert_equal true, generator.send(:migration_exists?, migration_name)
      assert_equal false, generator.send(:migration_exists?, "missing_migration.rb")

      timestamp = generator.send(:next_migration_number)
      assert_match(/\A\d{14}\z/, timestamp)
    end
  end

  def test_install_guide_includes_migration_and_host_setup_steps
    install_guide = File.read(INSTALL_TEMPLATE_PATH)

    assert_includes install_guide, "flat_pack"
    assert_includes install_guide, "recording_studio_recordable(...)"
    assert_includes install_guide, "RecordingStudio.enable_capability(:accessible"
    assert_includes install_guide, "bin/rails generate recording_studio_api:migrations"
    assert_includes install_guide, "bin/rails db:migrate"
    assert_includes install_guide, "auth, layout, and current actor integration"
  end

  private

  def assert_tailwind_sources_present(css)
    tailwind_source_lines.each do |line|
      assert_includes css, line
    end
  end

  def assert_tailwind_sources_count(css, count)
    tailwind_source_lines.each do |line|
      assert_equal count, css.scan(line).size
    end
  end

  def tailwind_source_lines
    [
      '@source "../../vendor/bundle/**/recording_studio_api/app/views/**/*.erb";',
      '@source "../../../../../../usr/local/bundle/ruby/**/bundler/gems/recording_studio_api-*/app/views/**/*.erb";',
      '@source "../../vendor/bundle/**/flatpack/app/components/**/*.{rb,erb}";',
      '@source "../../../../../../usr/local/bundle/ruby/**/bundler/gems/flatpack-*/app/components/**/*.{rb,erb}";'
    ]
  end
end
