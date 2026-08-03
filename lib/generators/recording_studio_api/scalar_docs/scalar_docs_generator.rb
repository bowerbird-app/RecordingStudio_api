# frozen_string_literal: true

require "rails/generators"
require "fileutils"

module RecordingStudioApi
  module Generators
    class ScalarDocsGenerator < Rails::Generators::NamedBase
      class_option :mount_path, type: :string, default: "/api-docs",
                                desc: "Path where the Scalar documentation is mounted"
      class_option :api_mount_path, type: :string, default: "/recording_studio_api",
                                    desc: "Path where RecordingStudioApi::Engine is mounted"
      class_option :api_surface, type: :string, default: "public",
                                 desc: "Named RecordingStudioApi surface to document"
      class_option :access, type: :string, default: "authenticated",
                            desc: "Documentation access mode: authenticated or public"
      class_option :layout, type: :string, default: nil,
                            desc: "Optional layout override for this API's documentation"

      desc "Installs routes and configuration for gem-owned Scalar API documentation"

      def validate_configuration
        errors = []
        errors << "NAME must contain letters, numbers, underscores, dashes, or slashes" unless valid_name?
        errors << "--mount-path must be a safe absolute path" unless valid_path?(mount_path)
        errors << "--api-mount-path must be a safe absolute path" unless valid_path?(api_mount_path, allow_root: true)
        errors << "--api-surface must contain letters, numbers, underscores, or dashes" unless api_name.match?(/\A[a-z0-9][a-z0-9_-]*\z/i)
        errors << "--access must be authenticated or public" unless %w[authenticated public].include?(access_mode)
        errors << "--layout must be a layout name" unless valid_layout?

        raise Thor::Error, "Scalar documentation generator failed: #{errors.join('; ')}" if errors.any?
      end

      def check_for_route_collisions
        return unless behavior == :invoke
        return unless File.exist?(routes_file_path)

        source = File.read(routes_file_path)
        return if source.include?(route_start_marker) && source.include?(route_end_marker)

        collisions = route_helper_names.select do |helper|
          source.match?(/as:\s*(?::#{Regexp.escape(helper)}\b|["']#{Regexp.escape(helper)}["'])/)
        end
        path_collisions = scalar_route_paths.select { |path| route_path_declared?(source, path) }
        return if collisions.empty? && path_collisions.empty?

        descriptions = []
        descriptions << "route helper (#{collisions.join(', ')})" if collisions.any?
        descriptions << "route path (#{path_collisions.join(', ')})" if path_collisions.any?
        raise Thor::Error, "Scalar documentation generator failed: route collision #{descriptions.join(' and ')}. Choose another NAME or mount path."
      end

      def add_routes
        return remove_marked_route_block if behavior == :revoke

        raise Thor::Error, "Scalar documentation generator failed: config/routes.rb was not found." unless File.exist?(routes_file_path)

        source = File.read(routes_file_path)
        if source.include?(route_start_marker)
          return say("Scalar documentation routes already exist for #{name}.", :yellow) if source.include?(route_block.strip)

          raise Thor::Error, "Scalar documentation generator failed: existing route block for #{name} differs from this configuration."
        end

        inject_into_file routes_path, "\n#{route_block}", before: /\nend\s*\z/
      end

      def create_configuration
        if behavior == :revoke
          configuration_file = File.join(destination_root, configuration_path)
          if File.exist?(configuration_file)
            say_status :remove, configuration_path
            FileUtils.rm_f(configuration_file) unless options[:pretend]
          end
          return
        end

        create_file configuration_path, configuration_source
      end

      def report_legacy_files
        legacy_paths = [
          File.join(destination_root, "app/controllers/#{file_name}/scalar_docs_controller.rb"),
          File.join(destination_root, "app/views/#{file_name}/scalar_docs")
        ].select { |path| File.exist?(path) }
        return if legacy_paths.empty?

        say "Legacy host-owned Scalar files remain and are no longer used by the generated routes: #{legacy_paths.join(', ')}", :yellow
      end

      private

      def mount_path
        @mount_path ||= normalized_path(options[:mount_path])
      end

      def api_mount_path
        @api_mount_path ||= normalized_path(options[:api_mount_path])
      end

      def api_name
        options[:api_surface].to_s.strip.downcase
      end

      def access_mode
        options[:access].to_s.strip.downcase
      end

      def route_key
        @route_key ||= file_name.tr("/", "_").parameterize(separator: "_")
      end

      def route_helper_names
        %W[
          #{route_key}_scalar_docs
          #{route_key}_scalar_docs_version
          #{route_key}_scalar_docs_openapi
          #{route_key}_scalar_docs_fullscreen
        ]
      end

      def scalar_route_paths
        [mount_path, "#{mount_path}/:version/openapi.json", "#{mount_path}/:version/fullscreen", "#{mount_path}/:version"]
      end

      def route_start_marker
        "# BEGIN RecordingStudioApi Scalar docs: #{route_key}"
      end

      def route_end_marker
        "# END RecordingStudioApi Scalar docs: #{route_key}"
      end

      def route_block
        <<~RUBY
          #{route_start_marker}
          recording_studio_api_scalar_docs_for :#{api_name},
            at: #{mount_path.inspect},
            as: :#{route_key}_scalar_docs,
            engine_mount_path: #{api_mount_path.inspect}
          #{route_end_marker}
        RUBY
      end

      def configuration_path
        "config/initializers/recording_studio_api_scalar_docs_#{route_key}.rb"
      end

      def configuration_source
        layout_assignment = if options[:layout].present?
                              "\n  api.documentation_layout_name = #{options[:layout].to_s.inspect}"
                            else
                              ""
                            end

        <<~RUBY
          # frozen_string_literal: true

          RecordingStudioApi.configure do |config|
            api = config.api(:#{api_name})
            api.documentation_enabled = true
            api.documentation_access = :#{access_mode}#{layout_assignment}
          end
        RUBY
      end

      def routes_path
        "config/routes.rb"
      end

      def routes_file_path
        File.join(destination_root, routes_path)
      end

      def normalized_path(value)
        path = value.to_s.strip
        path = "/#{path}" unless path.start_with?("/")
        path.squeeze("/").sub(%r{/\z}, "").presence || "/"
      end

      def valid_name?
        name.to_s.match?(%r{\A[a-zA-Z0-9][a-zA-Z0-9_/-]*\z}) && !name.to_s.include?("..")
      end

      def valid_path?(path, allow_root: false)
        return false if path == "/" && !allow_root

        path.match?(%r{\A/[a-zA-Z0-9._~!$&'+,;=@/-]*\z}) && !path.include?("..") && !path.include?("//")
      end

      def valid_layout?
        options[:layout].blank? || options[:layout].to_s.match?(%r{\A[a-zA-Z][a-zA-Z0-9_/-]*\z})
      end

      def route_path_declared?(source, path)
        quoted_path = %(["']#{Regexp.escape(path)}["'])
        source.match?(/\b(?:get|post|put|patch|delete|head|options)\s*(?:\(\s*)?#{quoted_path}/) ||
          source.match?(/\bmatch\s*(?:\(\s*)?#{quoted_path}/)
      end

      def remove_marked_route_block
        return unless File.exist?(routes_file_path)

        source = File.read(routes_file_path)
        pattern = /\n?#{Regexp.escape(route_start_marker)}.*?#{Regexp.escape(route_end_marker)}\n?/m
        updated_source = source.gsub(pattern, "")
        return say("No Scalar documentation route block found for #{name}.", :yellow) if source == updated_source

        say_status :remove, routes_path
        File.write(routes_file_path, updated_source) unless options[:pretend]
      end
    end
  end
end
