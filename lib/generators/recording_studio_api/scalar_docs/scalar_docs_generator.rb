# frozen_string_literal: true

require "rails/generators"
require "uri"

module RecordingStudioApi
  module Generators
    class ScalarDocsGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      DEFAULT_SCALAR_SOURCE = "https://cdn.jsdelivr.net/npm/@scalar/api-reference@1.25.118/dist/browser/standalone.js"
      # Add an entry only after fetching and verifying the exact immutable source bundle.
      DEFAULT_SCALAR_INTEGRITY_BY_SOURCE = {}.freeze

      class_option :mount_path, type: :string, default: "/api-docs",
                                desc: "Path where the Scalar documentation is mounted"
      class_option :api_mount_path, type: :string, default: "/recording_studio_api",
                                    desc: "Path where RecordingStudioApi::Engine is mounted"
      class_option :controller, type: :string, default: nil,
                                desc: "Controller path (defaults to NAME/scalar_docs)"
      class_option :layout, type: :string, default: "application",
                            desc: "Layout used by the embedded documentation page (or false)"
      class_option :scalar_source, type: :string, default: DEFAULT_SCALAR_SOURCE,
                                   desc: "Pinned Scalar standalone JavaScript URL"
      class_option :scalar_url, type: :string, default: nil,
                                desc: "OpenAPI URL for Scalar (defaults to the generated OpenAPI route)"
      class_option :scalar_integrity, type: :string, default: nil,
                                      desc: "Optional SRI hash for the Scalar script"
      class_option :default_api_version, type: :string, default: "v1",
                                        desc: "Default API version for the documentation redirect"
      class_option :openapi_provider, type: :string, default: "RecordingStudioApi::Services::OpenapiDocument",
                                      desc: "Callable OpenAPI provider constant"

      desc "Installs named, framework-agnostic Scalar API documentation"

      def validate_configuration
        validation_errors = []
        validation_errors << "NAME must contain letters, numbers, underscores, dashes, or slashes" unless valid_name?
        validation_errors << "--mount-path must be a safe absolute path" unless valid_path?(mount_path)
        validation_errors << "--api-mount-path must be a safe absolute path" unless valid_path?(api_mount_path, allow_root: true)
        validation_errors << "--default-api-version must look like v1" unless default_api_version.match?(/\Av[0-9][a-z0-9_-]*\z/i)
        validation_errors << "--controller must be a controller path" unless valid_controller?
        validation_errors << "--layout must be a layout name or false" unless valid_layout?
        validation_errors << "--scalar-source must be an http(s) URL" unless valid_http_url?(scalar_source)
        validation_errors << "--scalar-url must be blank, an absolute path, or an http(s) URL" unless valid_scalar_url?
        validation_errors << "--scalar-integrity must contain valid SRI sha256, sha384, or sha512 hashes" unless valid_scalar_integrity?
        validation_errors << "--openapi-provider must be a Ruby constant name" unless openapi_provider.match?(/\A[A-Z]\w*(?:::[A-Z]\w*)*\z/)

        raise Thor::Error, "Scalar documentation generator failed: #{validation_errors.join('; ')}" if validation_errors.any?
      end

      def check_for_route_collisions
        return unless behavior == :invoke
        return if options[:skip]
        return unless File.exist?(routes_file_path)

        source = File.read(routes_file_path)
        return if source.include?(route_start_marker) && source.include?(route_end_marker)

        collisions = route_helper_names.select do |helper|
          source.match?(/as:\s*(?::#{Regexp.escape(helper)}\b|["']#{Regexp.escape(helper)}["'])/)
        end
        path_collisions = scalar_route_paths.select { |path| route_path_declared?(source, path) }
        return if collisions.empty? && path_collisions.empty?

        collision_descriptions = []
        collision_descriptions << "route helper (#{collisions.join(', ')})" if collisions.any?
        collision_descriptions << "route path (#{path_collisions.join(', ')})" if path_collisions.any?
        raise Thor::Error, "Scalar documentation generator failed: route collision #{collision_descriptions.join(' and ')}. Choose another NAME or mount path."
      end

      def create_controller
        template "scalar_docs_controller.rb.erb", controller_file
      end

      def create_views
        template "show.html.erb", File.join(view_directory, "show.html.erb")
        template "fullscreen.html.erb", File.join(view_directory, "fullscreen.html.erb")
        template "_scalar.html.erb", File.join(view_directory, "_scalar.html.erb")
      end

      def add_routes
        if behavior == :revoke
          remove_marked_route_block
          return
        end

        if options[:skip]
          say "Skipping Scalar documentation routes for #{name}.", :yellow
          return
        end

        unless File.exist?(routes_file_path)
          raise Thor::Error, "Scalar documentation generator failed: #{routes_path} was not found."
        end

        source = File.read(routes_file_path)
        if source.include?(route_start_marker)
          if source.include?(route_block.strip)
            say "Scalar documentation routes already exist for #{name}.", :yellow
            return
          end

          raise Thor::Error, "Scalar documentation generator failed: existing route block for #{name} differs from this configuration."
        end

        inject_into_file routes_path, route_insertion, before: /\nend\s*\z/
      end

      def show_readme
        readme "README.md" if behavior == :invoke
      end

      private

      def mount_path
        @mount_path ||= normalized_path(options[:mount_path])
      end

      def scalar_source
        options[:scalar_source].to_s.strip
      end

      def scalar_integrity
        explicit_integrity = options[:scalar_integrity].to_s.strip.presence
        explicit_integrity || DEFAULT_SCALAR_INTEGRITY_BY_SOURCE[scalar_source]
      end

      def api_mount_path
        @api_mount_path ||= normalized_path(options[:api_mount_path])
      end

      def default_api_version
        version = options[:default_api_version].to_s.strip.downcase
        version.start_with?("v") ? version : "v#{version}"
      end

      def controller_path
        @controller_path ||= begin
          configured = options[:controller].presence || "#{file_name}/scalar_docs"
          configured.to_s.underscore.sub(%r{_controller\z}, "").tr("::", "/").squeeze("/")
        end
      end

      def controller_class_name
        "#{controller_path.camelize}Controller"
      end

      def controller_namespace
        controller_class_name.deconstantize.presence
      end

      def controller_short_class_name
        controller_class_name.demodulize
      end

      def controller_file
        File.join("app/controllers", "#{controller_path}_controller.rb")
      end

      def view_directory
        File.join("app/views", controller_path)
      end

      def route_key
        @route_key ||= file_name.tr("/", "_").parameterize(separator: "_")
      end

      def route_helper_names
        %W[
          #{route_key}_scalar_docs
          #{route_key}_scalar_docs_openapi
          #{route_key}_scalar_docs_fullscreen
        ]
      end

      def scalar_route_paths
        [
          mount_path,
          "#{mount_path}/:version/openapi.json",
          "#{mount_path}/:version/fullscreen",
          "#{mount_path}/:version"
        ]
      end

      def openapi_route_helper
        "#{route_key}_scalar_docs_openapi_path"
      end

      def fullscreen_route_helper
        "#{route_key}_scalar_docs_fullscreen_path"
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
          get "#{mount_path}", to: redirect("#{mount_path}/#{default_api_version}"), as: :#{route_key}_scalar_docs
          get "#{mount_path}/:version/openapi.json", to: "#{controller_path}#openapi", as: :#{route_key}_scalar_docs_openapi
          get "#{mount_path}/:version/fullscreen", to: "#{controller_path}#fullscreen", as: :#{route_key}_scalar_docs_fullscreen
          get "#{mount_path}/:version", to: "#{controller_path}#show"
          #{route_end_marker}
        RUBY
      end

      def route_insertion
        "\n#{route_block}"
      end

      def route_block_pattern
        /\n?#{Regexp.escape(route_start_marker)}.*?#{Regexp.escape(route_end_marker)}\n?/m
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
        name.to_s.match?(/\A[a-zA-Z0-9][a-zA-Z0-9_\/-]*\z/) && !name.to_s.include?("..")
      end

      def valid_path?(path, allow_root: false)
        return false if path == "/" && !allow_root

        path.match?(%r{\A/[a-zA-Z0-9._~!$&'()*+,;=@/-]*\z}) &&
          !path.include?("..") &&
          !path.include?("//")
      end

      def valid_controller?
        controller_path.match?(%r{\A[a-z][a-z0-9_]*(?:/[a-z][a-z0-9_]*)*\z})
      end

      def valid_layout?
        layout = options[:layout]
        layout == false || layout.to_s.match?(%r{\A[a-zA-Z][a-zA-Z0-9_/-]*\z})
      end

      def valid_http_url?(value)
        URI.parse(value.to_s).is_a?(URI::HTTP) && value.to_s.match?(/\Ahttps?:\/\//)
      rescue URI::InvalidURIError
        false
      end

      def valid_scalar_url?
        value = options[:scalar_url].to_s.strip
        value.blank? || valid_http_url?(value) || value.match?(%r{\A/[^\s"'<>\u0000]*\z})
      end

      def valid_scalar_integrity?
        integrity = scalar_integrity.to_s
        integrity.blank? || integrity.match?(%r{\Asha(?:256|384|512)-[A-Za-z0-9+/]+={0,2}(?:\s+sha(?:256|384|512)-[A-Za-z0-9+/]+={0,2})*\z})
      end

      def route_path_declared?(source, path)
        quoted_path = %(["']#{Regexp.escape(path)}["'])
        source.match?(/\b(?:get|post|put|patch|delete|head|options)\s*(?:\(\s*)?#{quoted_path}/) ||
          source.match?(/\bmatch\s*(?:\(\s*)?#{quoted_path}/)
      end

      def remove_marked_route_block
        return unless File.exist?(routes_file_path)

        source = File.read(routes_file_path)
        updated_source = source.gsub(route_block_pattern, "")
        return say "No Scalar documentation route block found for #{name}.", :yellow if source == updated_source

        say_status :remove, routes_path
        File.write(routes_file_path, updated_source) unless options[:pretend]
      end
    end
  end
end
