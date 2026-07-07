# frozen_string_literal: true

module RecordingStudioApi
  class AdminController < ApplicationController
    layout :recording_studio_api_admin_layout

    before_action :authenticate_user!, if: -> { respond_to?(:authenticate_user!, true) }
    before_action :assign_current_actor
    before_action :require_admin_root!
    before_action :load_admin_api_recording!
    before_action :authorize_admin_api_access!

    private

    def assign_current_actor
      return unless defined?(Current)
      return unless respond_to?(:current_user, true)
      return if current_user.blank?

      Current.actor = current_user
    end

    def require_admin_root!
      root_recording = current_root_recording
      raise RecordingStudioApi::AuthorizationError, "Admin API is only available from the admin root" if root_recording.nil?
      return if recording_studio_api_admin_root_recording?(root_recording)

      raise RecordingStudioApi::AuthorizationError, "Admin API is only available from the admin root"
    end

    def load_admin_api_recording!
      @admin_api = RecordingStudioApi::AdminApi.find_or_create_by!(key: "api") do |record|
        record.name = "Admin API"
      end

      @admin_api_recording = RecordingStudio::Recording.unscoped.find_or_create_by!(
        recordable: @admin_api,
        root_recording_id: current_root_recording.id,
        parent_recording_id: current_root_recording.id
      )

      @admin_api = @admin_api_recording.recordable
    end

    def authorize_admin_api_access!
      return if RecordingStudioAccessible.authorized?(
        actor: current_request_actor,
        recording: @admin_api_recording,
        role: RecordingStudioApi.configuration.access_management_view_role
      )

      raise RecordingStudioApi::AuthorizationError, "Admin API is not available for the current actor"
    end

    def current_request_actor
      return current_user if respond_to?(:current_user, true) && current_user.present?
      return Current.actor if defined?(Current) && Current.respond_to?(:actor)

      nil
    end

    def page_nav_default_close_url
      RecordingStudioApi.admin_dashboard_path(controller: self)
    end
  end
end