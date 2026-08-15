# frozen_string_literal: true

require "rails/generators"

module RecordingStudioApi
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Installs RecordingStudioApi engine into your application"

      class_option(
        :mount_path,
        type: :string,
        default: "/recording_studio_api",
        desc: "Route prefix used when mounting the engine"
      )

      def mount_engine
        route %(mount RecordingStudioApi::Engine, at: "#{options[:mount_path]}")
      end

      def copy_initializer
        template "recording_studio_api_initializer.rb", "config/initializers/recording_studio_api.rb"
      end

      def add_yaml_config
        return unless yes?("Would you like to add `config/recording_studio_api.yml` for environment-specific settings? [y/N]")

        template "recording_studio_api.yml", "config/recording_studio_api.yml"
      end

      def add_tailwind_source
        tailwind_css_path = Rails.root.join("app/assets/tailwind/application.css")
        return show_missing_tailwind_notice unless File.exist?(tailwind_css_path)

        tailwind_content = File.read(tailwind_css_path)
        missing_lines = missing_tailwind_source_lines(tailwind_content)

        if missing_lines.empty?
          say "Tailwind already configured to include RecordingStudioApi and FlatPack sources.", :green
          return
        end

        if tailwind_content.include?('@import "tailwindcss"')
          inject_tailwind_sources(tailwind_css_path, missing_lines)
          return
        end

        show_manual_tailwind_notice(missing_lines)
      end

      def show_readme
        readme "INSTALL.md" if behavior == :invoke
      end

      private

      def show_missing_tailwind_notice
        say "Tailwind CSS not detected. Skipping Tailwind configuration.", :yellow
        say "If you use Tailwind, add these lines to your Tailwind CSS config:", :yellow
        tailwind_source_lines.each do |line|
          say "  #{line}", :yellow
        end
      end

      def missing_tailwind_source_lines(tailwind_content)
        tailwind_source_lines.reject { |line| tailwind_content.include?(line) }
      end

      def inject_tailwind_sources(tailwind_css_path, missing_lines)
        inject_into_file tailwind_css_path, after: "@import \"tailwindcss\";\n" do
          "#{formatted_tailwind_source_block(missing_lines)}\n"
        end
        say "Added RecordingStudioApi and FlatPack sources to Tailwind CSS configuration.", :green
        say "Run 'bin/rails tailwindcss:build' to rebuild your CSS.", :green
      end

      def formatted_tailwind_source_block(missing_lines)
        engine_lines = missing_lines.select { |line| line.include?("recording_studio_api") }
        flat_pack_lines = missing_lines - engine_lines

        [
          "\n/* Include RecordingStudioApi engine views for Tailwind CSS */",
          engine_lines,
          "\n/* Include FlatPack component sources for Tailwind CSS */",
          flat_pack_lines
        ].flatten.reject(&:empty?).join("\n")
      end

      def show_manual_tailwind_notice(missing_lines)
        say "Could not find @import \"tailwindcss\" in your Tailwind config.", :yellow
        say "Please manually add these lines to your Tailwind CSS config:", :yellow
        missing_lines.each do |line|
          say "  #{line}", :yellow
        end
      end

      def tailwind_source_lines
        [
          '@source "../../vendor/bundle/**/recording_studio_api/app/views/**/*.erb";',
          '@source "../../../../../../usr/local/bundle/ruby/**/bundler/gems/' \
          'recording_studio_api-*/app/views/**/*.erb";',
          # GitHub gem checkout directory is flatpack-*; gem name is flat_pack.
          '@source "../../vendor/bundle/**/flatpack*/app/components/**/*.{rb,erb}";',
          '@source "../../vendor/bundle/**/flat_pack*/app/components/**/*.{rb,erb}";',
          '@source "../../../../../../usr/local/bundle/ruby/**/bundler/gems/' \
          'flatpack-*/app/components/**/*.{rb,erb}";',
          '@source "../../../../../../usr/local/bundle/ruby/**/bundler/gems/' \
          'flat_pack-*/app/components/**/*.{rb,erb}";',
          *resolved_flat_pack_source_lines
        ]
      end

      def resolved_flat_pack_source_lines
        return [] unless defined?(FlatPack::Engine)

        components = FlatPack::Engine.root.join("app/components")
        return [] unless components.exist?

        tailwind_css_path = Rails.root.join("app/assets/tailwind/application.css")
        relative = components.relative_path_from(tailwind_css_path.dirname)
        [%(@source "#{relative}";)]
      rescue StandardError
        []
      end
    end
  end
end
