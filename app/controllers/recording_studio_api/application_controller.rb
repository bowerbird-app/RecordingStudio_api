# frozen_string_literal: true

module RecordingStudioApi
  class ApplicationController < ActionController::Base
    include RecordingStudio::RootSwitchable::ControllerSupport if defined?(RecordingStudio::RootSwitchable::ControllerSupport)

    helper_method :admin_root_current?
    helper_method :current_root_name

    protect_from_forgery with: :exception
    layout :recording_studio_api_layout

    rescue_from RecordingStudioApi::AuthorizationError do
      head :forbidden
    end

    private

    def recording_studio_api_layout
      RecordingStudioApi.configuration.layout_name.presence || "application"
    end

    def recording_studio_api_admin_layout
      RecordingStudioApi.configuration.admin_layout_name.presence || recording_studio_api_layout
    end

    def admin_root_current?
      current_root = current_root_recording if respond_to?(:current_root_recording, true)
      return false if current_root.blank?
      return false unless defined?(RecordingStudioAdmin) && RecordingStudioAdmin.respond_to?(:admin_root_recording?)

      RecordingStudioAdmin.admin_root_recording?(current_root)
    end

    def current_root_name
      recordable = current_root_recordable if respond_to?(:current_root_recordable, true)
      return "No current root" if recordable.blank?

      if recordable.respond_to?(:name) && recordable.name.present?
        recordable.name
      elsif defined?(RecordingStudio::Labels)
        RecordingStudio::Labels.title_for(recordable)
      else
        recordable.to_s
      end
    end

    def turbo_frame_request?
      request.headers["Turbo-Frame"].present?
    end
  end
end
