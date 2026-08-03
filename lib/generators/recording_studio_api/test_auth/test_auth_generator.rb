# frozen_string_literal: true

require "rails/generators"

module RecordingStudioApi
  module Generators
    class TestAuthGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      class_option :mount_path, type: :string, default: "/api-docs",
                                desc: "Mount path used by the matching Scalar documentation installation"
      class_option :api_surface, type: :string, default: "public",
                                 desc: "Named RecordingStudioApi surface used for generated credentials"
      class_option :controller, type: :string, default: nil,
                                desc: "Scalar controller path (defaults to NAME/scalar_docs)"

      desc "Installs an optional local test-token page for a generated API reference"

      def validate_configuration
        errors = []
        errors << "NAME must contain letters, numbers, underscores, dashes, or slashes" unless valid_name?
        errors << "--mount-path must be a safe absolute path" unless valid_mount_path?
        errors << "--api-surface must contain letters, numbers, underscores, or dashes" unless api_name.match?(/\A[a-z0-9][a-z0-9_-]*\z/i)
        errors << "--controller must be a controller path" unless controller_path.match?(%r{\A[a-z][a-z0-9_]*(?:/[a-z][a-z0-9_]*)*\z})

        raise Thor::Error, "Test auth generator failed: #{errors.join('; ')}" if errors.any?
      end

      def ensure_scalar_installation
        return if behavior == :revoke

        scalar_routes_installed = File.exist?(routes_file_path) &&
                                  File.read(routes_file_path).match?(/recording_studio_api_scalar_docs_for\s+:#{Regexp.escape(api_name)}.*?as:\s*:#{Regexp.escape(route_key)}_scalar_docs\b/m)
        return if scalar_routes_installed

        raise Thor::Error, "Test auth generator failed: install matching gem-owned Scalar docs before adding test auth."
      end

      def check_for_route_collisions
        return if behavior == :revoke

        source = File.read(routes_file_path)
        return if source.include?(route_start_marker)

        helper_collision = source.match?(/as:\s*:#{Regexp.escape(route_key)}_scalar_test_credential\b/)
        path_collision = source.match?(/["']#{Regexp.escape("#{mount_path}/:version/test-credential")}["']/)
        return unless helper_collision || path_collision

        raise Thor::Error, "Test auth generator failed: route collision for #{mount_path}/:version/test-credential."
      end

      def create_controller
        template "scalar_test_credentials_controller.rb.erb", credentials_controller_file
      end

      def create_concern
        template "scalar_test_auth.rb.erb", concern_file
      end

      def create_view
        template "test_auth.html.erb", test_auth_view_file
      end

      def add_routes
        if behavior == :revoke
          remove_marked_block(routes_file_path, route_start_marker, route_end_marker)
          return
        end

        source = File.read(routes_file_path)
        return say("Test auth routes already exist for #{name}.", :yellow) if source.include?(route_start_marker)

        inject_into_file "config/routes.rb", "\n#{route_block}", before: /\nend\s*\z/
      end

      private

      def api_name
        options[:api_surface].to_s.strip.downcase
      end

      def mount_path
        @mount_path ||= begin
          path = options[:mount_path].to_s.strip
          path = "/#{path}" unless path.start_with?("/")
          path.squeeze("/").sub(%r{/\z}, "")
        end
      end

      def controller_path
        @controller_path ||= begin
          configured = options[:controller].presence || "#{file_name}/scalar_docs"
          configured.to_s.underscore.sub(/_controller\z/, "").tr("::", "/").squeeze("/")
        end
      end

      def controller_namespace_path
        File.dirname(controller_path) == "." ? nil : File.dirname(controller_path)
      end

      def controller_namespace
        controller_namespace_path&.camelize
      end

      def credentials_controller_path
        [controller_namespace_path, "scalar_test_credentials"].compact.join("/")
      end

      def credentials_controller_namespace
        controller_namespace
      end

      def concern_path
        [controller_namespace_path, "scalar_test_auth"].compact.join("/")
      end

      def concern_module_name
        concern_path.camelize
      end

      def credentials_controller_file
        "app/controllers/#{credentials_controller_path}_controller.rb"
      end

      def concern_file
        "app/controllers/concerns/#{concern_path}.rb"
      end

      def test_auth_view_file
        "app/views/#{credentials_controller_path}/show.html.erb"
      end

      def route_key
        @route_key ||= file_name.tr("/", "_").parameterize(separator: "_")
      end

      def version_route_helper
        "#{route_key}_scalar_docs_version_path"
      end

      def credential_route_helper
        "#{route_key}_scalar_test_credential_path"
      end

      def credentials_route_controller
        credentials_controller_path
      end

      def session_key
        "recording_studio_api.#{route_key}.test_credential"
      end

      def route_start_marker
        "# BEGIN RecordingStudioApi test auth routes: #{route_key}"
      end

      def route_end_marker
        "# END RecordingStudioApi test auth routes: #{route_key}"
      end

      def route_block
        <<~RUBY
          #{route_start_marker}
          get "#{mount_path}/:version/test-credential", to: "#{credentials_route_controller}#show", as: :#{route_key}_scalar_test_credential
          post "#{mount_path}/:version/test-credential", to: "#{credentials_route_controller}#create"
          delete "#{mount_path}/:version/test-credential", to: "#{credentials_route_controller}#destroy"
          #{route_end_marker}
        RUBY
      end

      def routes_file_path
        File.join(destination_root, "config/routes.rb")
      end

      def valid_name?
        name.to_s.match?(%r{\A[a-zA-Z0-9][a-zA-Z0-9_/-]*\z}) && !name.to_s.include?("..")
      end

      def valid_mount_path?
        mount_path.match?(%r{\A/[a-zA-Z0-9._~!$&'+,;=@/-]+\z}) && !mount_path.include?("..") && !mount_path.include?("//")
      end

      def remove_marked_block(path, start_marker, end_marker)
        return unless File.exist?(path)

        source = File.read(path)
        pattern = /\n?\s*#{Regexp.escape(start_marker)}.*?#{Regexp.escape(end_marker)}\s*\n?/m
        updated = source.sub(pattern, "\n")
        return if source == updated

        say_status :remove, relative_path(path)
        File.write(path, updated) unless options[:pretend]
      end

      def relative_path(path)
        Pathname.new(path).relative_path_from(Pathname.new(destination_root)).to_s
      end
    end
  end
end