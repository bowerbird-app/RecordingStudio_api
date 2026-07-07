# frozen_string_literal: true

module RecordingStudioApi
  class ApplicationController < ActionController::Base
    include RecordingStudio::RootSwitchable::ControllerSupport if defined?(RecordingStudio::RootSwitchable::ControllerSupport)

    helper RecordingStudio::LayoutHelper if defined?(RecordingStudio::LayoutHelper)

    helper_method :admin_root_current?
    helper_method :current_root_name
    helper_method :page_nav_close_url
    helper_method :page_nav_close_param

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

      recording_studio_api_admin_root_recording?(current_root)
    end

    def recording_studio_api_admin_root_recording?(recording)
      return false unless defined?(RecordingStudioAdmin)

      recordable = recording.recordable if recording.respond_to?(:recordable)
      return false unless recordable&.class.respond_to?(:recording_studio_admin_section_keys_for)

      context = RecordingStudioAdmin::Context.new(
        params: {},
        current_actor: recording_studio_api_current_actor,
        controller: self,
        routes: self
      )
      keys = recordable.class.recording_studio_admin_section_keys_for(recordable, recording, context)
      Array(keys).map(&:to_s).include?("api_admin")
    end

    def recording_studio_api_current_actor
      return current_user if respond_to?(:current_user, true) && current_user.present?
      return Current.actor if defined?(Current) && Current.respond_to?(:actor)

      nil
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

    def page_nav_close_url
      @page_nav_close_url ||= sanitized_page_nav_close_url(params[:close_url]) || page_nav_default_close_url
    end

    def page_nav_close_param
      return {} if page_nav_close_url.blank?

      { close_url: page_nav_close_url }
    end

    def page_nav_default_close_url
      main_app.root_path
    end

    def sanitized_page_nav_close_url(raw_url)
      return if raw_url.blank?

      sanitized_url = FlatPack::AttributeSanitizer.sanitize_url(raw_url)
      return unless sanitized_url.present?
      return if sanitized_url.start_with?("//")

      uri = URI.parse(sanitized_url)
      path = uri.path.to_s
      return unless path.start_with?("/")

      [path, uri.query.present? ? "?#{uri.query}" : nil, uri.fragment.present? ? "##{uri.fragment}" : nil].compact.join
    rescue URI::InvalidURIError
      nil
    end
  end
end
