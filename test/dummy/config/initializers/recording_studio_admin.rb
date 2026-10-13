# frozen_string_literal: true

RecordingStudioAdmin.configure do |config|
  config.default_mount_path = "/admin"
  config.authentication_method = :authenticate_user!
  config.current_actor_method = :current_user
  config.access_recording_resolver = lambda do |context|
    current_root = context.controller.send(:current_root_recording) if context.controller.respond_to?(:current_root_recording, true)
    next current_root if current_root.present?

    admin_root = AdminRoot.find_by(name: "Admin")
    next unless admin_root

    RecordingStudio::Recording.find_by(recordable: admin_root, trashed_at: nil)
  end
  config.site_admin_recording_resolver = config.access_recording_resolver
  config.engine_layout = RecordingStudioApi.configuration.layout_name.presence || "application"
end

Rails.application.config.to_prepare do
  if defined?(RecordingStudioAdmin::ApplicationController) && defined?(RecordingStudioAccessible::AvatarsHelper)
    RecordingStudioAdmin::ApplicationController.include RecordingStudioAccessible::AvatarsHelper
    RecordingStudioAdmin::ApplicationController.helper RecordingStudioAccessible::AvatarsHelper
  end

  if defined?(RecordingStudioAdmin::ApplicationController)
    RecordingStudioAdmin::ApplicationController.class_eval do
      helper_method :admin_root_current?, :recording_studio_accessible_avatars
      alias_method :recording_studio_api_original_page_nav_anchor_url, :page_nav_anchor_url unless method_defined?(:recording_studio_api_original_page_nav_anchor_url)

      private

      def page_nav_anchor_url(default: nil)
        surface_path = recording_studio_admin_surface&.path
        surface_default = default == RecordingStudioAdmin.configuration.default_mount_path ? surface_path : default

        recording_studio_api_original_page_nav_anchor_url(default: surface_default)
      end

      def admin_root_current?
        true
      end

      def recording_studio_accessible_avatars(*)
        "".html_safe
      end
    end
  end
end
