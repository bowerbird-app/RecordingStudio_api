# frozen_string_literal: true

module RecordingStudioApi
  module AccessRequests
    module FormState
      extend ActiveSupport::Concern

      included do
        helper_method :human_root_type,
                      :allowed_root_types,
                      :recording_label,
                      :masked_api_key
      end

      private

      def load_form_state
        @errors = []
        @root_type = normalized_root_type
        @root_recording = selected_root_recording
        @access_point_recordings = available_access_point_recordings(@root_recording)
        @role_options = role_options
        @api_options = RecordingStudioApi.configuration.each_api.map { |api| [api.name.humanize, api.name] }
        access_point_recording = selected_access_point_recording
        @form_values = {
          root_type: @root_type,
          root_recording_id: @root_recording&.id,
          access_point_recording_id: api_client_params[:access_point_recording_id].presence || access_point_recording&.id,
          role: api_client_params[:role].presence || "view",
          api_client_name: api_client_params[:api_client_name].presence || default_api_client_name,
          expires_at: api_client_params[:expires_at].to_s,
          api_key: selected_api.name
        }
      end

      def load_edit_form_state
        @errors = []
        @root_recording = @api_client.access_recording&.root_recording
        @access_point_recordings = available_access_point_recordings(@root_recording)
        @role_options = role_options
        @api_options = [[@api_client.api_key.humanize, @api_client.api_key]]
        @form_values = {
          access_point_recording_id: api_client_update_params[:access_point_recording_id].presence || access_point_recording_for(@api_client.access_recording)&.id,
          role: api_client_update_params[:role].presence || resolved_edit_role_value,
          api_client_name: api_client_update_params[:api_client_name].presence || @api_client.name,
          expires_at: resolved_edit_expires_at_value,
          api_key: @api_client.api_key
        }
      end

      def api_client_params
        params.fetch(:api_client, params.fetch(:access_request, {})).permit(:root_type, :root_recording_id, :access_point_recording_id, :role, :api_client_name, :expires_at, :api_key)
      end

      def selected_api
        RecordingStudioApi.configuration.fetch_api(api_client_params[:api_key].presence || params[:api_key].presence || :public)
      end

      def api_client_update_params
        params.fetch(:api_client, params.fetch(:access_request, {})).permit(:access_point_recording_id, :role, :api_client_name, :expires_at)
      end

      def normalized_root_type
        root_recording = selected_root_recording
        return root_recording.recordable_type if root_recording.present?

        requested_root_type = requested_root_type_value
        allowed_root_types.include?(requested_root_type) ? requested_root_type : allowed_root_types.first
      end

      def allowed_root_types
        @allowed_root_types ||= manageable_root_recordings.map(&:recordable_type).uniq &
                                RecordingStudioApi.api_recordable_types(api: selected_api.name)
      end

      def available_root_recordings(root_type)
        return [] if root_type.blank?

        manageable_root_recordings.select { |recording| recording.recordable_type == root_type }
      end

      def available_access_point_recordings(root_recording)
        access_point_types = RecordingStudioApi.api_access_point_recordable_types(api: selected_api.name)
        return [] if access_point_types.empty?

        roots = root_recording.present? ? [root_recording] : manageable_root_recordings
        recordings = roots.flat_map do |available_root_recording|
          available_root_recording.subtree_recordings(include_self: true)
            .includes(:recordable)
            .where(recordable_type: access_point_types, trashed_at: nil)
            .reorder(:created_at, :id)
            .to_a
        end

        recordings.uniq { |recording| recording.id }
      end

      def selected_root_recording
        @selected_root_recording ||= begin
          recording = RecordingStudio::Recording.includes(:recordable).find_by(id: requested_root_recording_id) if requested_root_recording_id.present?
          recording = nil unless manageable_root_recording?(recording)
          recording ||= available_root_recordings(requested_root_type_value).first if requested_root_type_value.present?
          recording || manageable_root_recordings.find { |candidate| allowed_root_types.include?(candidate.recordable_type) }
        end
      end

      def role_options
        %w[view edit admin].map { |value| [value.humanize, value] }
      end

      def default_api_client_name
        "My api access"
      end

      def selected_access_point_recording
        @selected_access_point_recording ||= begin
          requested_recording = @access_point_recordings.find { |recording| recording.id == requested_id } if requested_id.present?
          requested_recording || @access_point_recordings.first unless requested_access_point_recording_id.present? && requested_recording.nil?
        end
      end

      def requested_root_type_value
        api_client_params[:root_type].presence || params[:root_type].presence
      end

      def requested_root_recording_id
        api_client_params[:root_recording_id].presence || params[:root_recording_id].presence
      end

      def requested_id
        requested_access_point_recording_id || requested_root_recording_id
      end

      def requested_access_point_recording_id
        api_client_params[:access_point_recording_id].presence ||
          params[:access_point_recording_id].presence ||
          params[:parent_recording_id].presence ||
          params[:recording_id].presence
      end

      def parsed_expires_at
        raw_value = @form_values.fetch(:expires_at)
        return nil if raw_value.blank?

        parsed_value = Time.zone.parse(raw_value)
        return parsed_value if parsed_value.present?

        @errors << "Expiry must be a valid date and time"
        nil
      rescue ArgumentError
        @errors << "Expiry must be a valid date and time"
        nil
      end

      def parsed_edit_expires_at
        raw_value = @form_values.fetch(:expires_at)
        return nil if raw_value.blank?

        parsed_value = Time.zone.parse(raw_value)
        return parsed_value if parsed_value.present?

        @errors << "Expiry must be a valid date and time"
        nil
      rescue ArgumentError
        @errors << "Expiry must be a valid date and time"
        nil
      end

      def render_invalid_form
        @errors << "An access point recording must be selected" if selected_access_point_recording.nil?
        render :new, status: :unprocessable_entity
      end

      def human_root_type
        @root_type.to_s.demodulize.underscore.humanize
      end

      def resolved_edit_role_value
        @access_recording&.recordable&.try(:role).to_s.presence || "admin"
      end

      def resolved_edit_expires_at_value
        return api_client_update_params[:expires_at].to_s if api_client_update_params.key?(:expires_at)

        datetime_local_value(@latest_credential&.expires_at)
      end

      def datetime_local_value(value)
        return "" if value.blank?

        value.in_time_zone.strftime("%Y-%m-%dT%H:%M")
      end

      def selected_edit_access_point_recording
        @access_point_recordings.find { |recording| recording.id == @form_values.fetch(:access_point_recording_id) }
      end
    end
  end
end
