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
        :admin_roots,
        type: :array,
        default: [],
        desc: "Root recordable models that should expose site-wide API administration screens"
      )

      class_option(
        :apis,
        type: :array,
        default: ["public"],
        desc: "Deprecated shorthand for applying the same APIs to user and admin screens"
      )

      class_option(
        :user_apis,
        type: :array,
        default: nil,
        desc: "Configured API surfaces that should receive user-facing credential screens"
      )

      class_option(
        :admin_apis,
        type: :array,
        default: nil,
        desc: "Configured API surfaces that should receive site administration screens"
      )

      class_option(
        :api_mount_path,
        type: :string,
        default: "/api",
        desc: "Route prefix used by the user-facing API admin surface"
      )

      class_option(
        :admin_api_mount_path,
        type: :string,
        default: "/admin/api",
        desc: "Base route prefix used by site-wide API administration surfaces"
      )

      def validate_configured_apis
        (user_api_names | admin_api_names).each do |api_name|
          RecordingStudioApi.configuration.fetch_api(api_name)
        end
      end

      def add_api_route
        user_api_names.each do |api_name|
          route %(recording_studio_admin_for :#{user_surface_key(api_name)}, at: "#{surface_path(options[:api_mount_path], api_name)}", root_section: :#{user_section_key(api_name)})
        end
      end

      def add_admin_api_routes
        return if admin_root_names.empty?

        admin_api_names.each do |api_name|
          route %(recording_studio_admin_for :#{admin_surface_key(api_name)}, at: "#{surface_path(options[:admin_api_mount_path], api_name)}", root_section: :#{admin_section_key(api_name)})
        end
      end

      def add_user_api_sections
        user_root_names.each do |model_name|
          user_api_names.each { |api_name| add_section_to_model(model_name, user_section_key(api_name)) }
        end
      end

      def add_admin_api_sections
        admin_root_names.each do |model_name|
          admin_api_names.each { |api_name| add_section_to_model(model_name, admin_section_key(api_name)) }
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

      def admin_root_names
        Array(options[:admin_roots]).flat_map { |entry| entry.to_s.split(",") }.map(&:strip).reject(&:blank?)
      end

      def user_api_names
        api_names_for(:user_apis)
      end

      def admin_api_names
        api_names_for(:admin_apis)
      end

      def api_names_for(option_name)
        configured_names = Array(options[option_name])
        configured_names = Array(options[:apis]) if configured_names.empty?

        configured_names.flat_map { |entry| entry.to_s.split(",") }
                        .map { |entry| RecordingStudioApi.configuration.canonical_api_name(entry) }
                        .reject(&:blank?)
                        .uniq
      end

      def user_section_key(api_name)
        api_name == "public" ? :api : :"#{api_name}_api"
      end

      def admin_section_key(api_name)
        api_name == "public" ? :admin_api : :"admin_#{api_name}_api"
      end

      def user_surface_key(api_name)
        user_section_key(api_name)
      end

      def admin_surface_key(api_name)
        admin_section_key(api_name)
      end

      def surface_path(base_path, api_name)
        return base_path if api_name == "public"

        "#{base_path.to_s.sub(%r{/\z}, '')}/#{api_name}"
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