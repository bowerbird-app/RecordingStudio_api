# frozen_string_literal: true

require "rails/generators"

module RecordingStudioApi
  module Generators
    class AdminScreensGenerator < Rails::Generators::Base
      desc "Installs RecordingStudioAdmin screen wiring for RecordingStudioApi"

      class_option(
        :user_roots,
        type: :array,
        default: [],
        desc: "Root recordable models that should expose user API key screens"
      )

      class_option(
        :api_mount_path,
        type: :string,
        default: "/api",
        desc: "Route prefix used by the user-facing API admin surface"
      )

      def add_api_route
        route %(recording_studio_admin_for :api, at: "#{options[:api_mount_path]}", root_section: :api)
      end

      def add_user_api_sections
        user_root_names.each do |model_name|
          add_section_to_model(model_name, :api)
        end
      end

      def show_readme
        say "RecordingStudioApi Admin screens are registered by the engine when recording_studio_admin is available.", :green
        say "Grant users access to the selected roots through RecordingStudioAccessible before using the screens.", :green
      end

      private

      def user_root_names
        Array(options[:user_roots]).flat_map { |entry| entry.to_s.split(",") }.map(&:strip).reject(&:blank?)
      end

      def add_section_to_model(model_name, section_key)
        path = model_path(model_name)
        unless File.exist?(path)
          say "Skipping #{model_name}: #{relative_model_path(model_name)} was not found.", :yellow
          return
        end

        ensure_admin_sections_include(path, model_name)
        ensure_admin_section_declaration(path, section_key)
      end

      def ensure_admin_sections_include(path, model_name)
        source = File.read(path)
        return if source.include?("include RecordingStudioAdmin::AllowsAdminSections")

        class_line = "class #{model_name} < ApplicationRecord\n"
        unless source.include?(class_line)
          say "Skipping include for #{model_name}: expected #{class_line.strip.inspect}.", :yellow
          return
        end

        inject_into_file relative_path(path), "  include RecordingStudioAdmin::AllowsAdminSections\n\n", after: class_line
      end

      def ensure_admin_section_declaration(path, section_key)
        source = File.read(path)
        section_line = "    section :#{section_key}"
        return if source.include?(section_line)

        if source.include?("recording_studio_admin_sections do\n")
          inject_into_file relative_path(path), "#{section_line}\n", after: "recording_studio_admin_sections do\n"
          return
        end

        insert_before_final_end(path, <<~RUBY)

          recording_studio_admin_sections do
            section :#{section_key}
          end
        RUBY
      end

      def insert_before_final_end(path, content)
        source = File.read(path)
        insertion_index = source.rindex("\nend")
        unless insertion_index
          say "Skipping admin section declaration for #{relative_path(path)}: final end was not found.", :yellow
          return
        end

        updated_source = source.dup.insert(insertion_index, content)
        File.write(path, updated_source)
      end

      def model_path(model_name)
        File.join(destination_root, relative_model_path(model_name))
      end

      def relative_model_path(model_name)
        File.join("app/models", "#{model_name.to_s.underscore}.rb")
      end

      def relative_path(path)
        Pathname.new(path).relative_path_from(Pathname.new(destination_root)).to_s
      end
    end
  end
end