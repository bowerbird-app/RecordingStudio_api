# frozen_string_literal: true

module RecordingStudioApi
  module AccessRequests
    module PolicyHelpers
      extend ActiveSupport::Concern

      private

      def current_request_actor
        return current_user if respond_to?(:current_user, true) && current_user.present?
        return Current.actor if defined?(Current) && Current.respond_to?(:actor)

        nil
      end

      def access_management_policy
        @access_management_policy ||= RecordingStudioApi::AccessManagementPolicy.new(actor: current_request_actor)
      end

      def api_client_management_policy
        @api_client_management_policy ||= RecordingStudioApi::ApiClientManagementPolicy.new(actor: current_request_actor)
      end

      def visible_access_recordings
        access_management_policy.visible_access_recordings
      end

      def visible_api_client_access_recordings
        access_management_policy.visible_api_client_access_recordings
      end

      def visible_api_client_ids
        @visible_api_client_ids ||= RecordingStudioApi::ApiClient
                                    .includes(access_recording: [:recordable, { parent_recording: :parent_recording }])
                                    .where(access_recording_id: visible_api_client_access_recordings.map(&:id))
                                    .select { |api_client| api_client_management_policy.view?(api_client) }
                                    .map(&:id)
      end

      def visible_root_recordings
        access_management_policy.visible_root_recordings
      end

      def manageable_root_recordings
        access_management_policy.manageable_root_recordings
      end

      def authorize_access_management_edit_for_new_request!
        access_point_recording = selected_access_point_recording_for_request
        return if access_management_policy.can_manage_recording?(access_point_recording) && authorized_to_manage_selected_api?(access_point_recording)

        raise RecordingStudioApi::AuthorizationError, "API access management requires higher access"
      end

      def authorized_to_manage_selected_api?(access_point_recording)
        api = selected_api
        return true unless api.api_management_authorization_required
        return false if access_point_recording.nil?

        root_recording = access_point_recording.root_recording || access_point_recording
        return false unless RecordingStudioApi.configuration.admin_root_recordable_type_names.include?(root_recording.recordable_type)

        RecordingStudioApi::Admin::ApiAuthorization.authorized?(
          actor: current_request_actor,
          api: api,
          root_recording: root_recording,
          role: RecordingStudioApi.configuration.access_management_edit_role,
          create: true
        )
      end

      def authorize_access_management_edit_for_loaded_client!
        return if api_client_management_policy.manage?(@api_client)

        raise RecordingStudioApi::AuthorizationError, "API access management requires higher access"
      end

      def selected_access_point_recording_for_request
        access_point_recordings = available_access_point_recordings(selected_root_recording)
        requested_recording = access_point_recordings.find { |recording| recording.id == requested_id } if requested_id.present?
        return requested_recording if requested_access_point_recording_id.present? || requested_recording.present?

        access_point_recordings.first
      end

      def manageable_root_recording?(recording)
        return false if recording.nil? || recording.parent_recording_id.present?

        manageable_root_recordings.any? { |candidate| candidate.id == recording.id }
      end

      def access_point_recording_for(access_recording)
        parent_recording = access_recording.parent_recording

        return access_recording.root_recording if parent_recording.nil?

        parent_recording
      end

      def access_point_label(recording)
        return "Unknown" if recording.nil?

        if recording.parent_recording_id.nil?
          return recording.recordable_type.to_s.demodulize.underscore.humanize
        end

        recordable_identifier(recording.recordable)
      end

      def credential_status_label(credential)
        return "No credentials" if credential.nil?
        return "Revoked" if credential.revoked_at.present?
        return "Expired" if credential.expires_at.present? && credential.expires_at.past?

        "Active"
      end

      def recording_label(recording)
        type_label = recording.recordable_type.to_s.demodulize.underscore.humanize
        identifier = recordable_identifier(recording.recordable)

        "#{type_label}: #{identifier}"
      end

      def recordable_identifier(recordable)
        return "Unknown recordable" if recordable.nil?

        %i[name title email label slug identifier].each do |attribute|
          next unless recordable.respond_to?(attribute)

          value = recordable.public_send(attribute)
          return value if value.present?
        end

        actor = recordable.actor if recordable.respond_to?(:actor)
        actor_email = actor.email if actor.respond_to?(:email) && actor.email.present?

        if recordable.respond_to?(:role) && recordable.role.present? && actor_email.present?
          return "#{recordable.role.to_s.humanize} for #{actor_email}"
        end

        return recordable.role.to_s.humanize if recordable.respond_to?(:role) && recordable.role.present?

        "Unknown recordable"
      end

      def masked_api_key(credential)
        oauth_client_id = credential&.oauth_client_id.to_s
        return "Unavailable" if oauth_client_id.blank?

        visible_prefix = oauth_client_id.first(2)
        visible_suffix = oauth_client_id.last(2)
        masked_length = [oauth_client_id.length - 4, 0].max

        "#{visible_prefix}#{"*" * masked_length}#{visible_suffix}"
      end
    end
  end
end
