# frozen_string_literal: true

module RecordingStudioApi
  module AccessRequests
    module DetailLoading
      extend ActiveSupport::Concern

      private

      def load_api_access_detail
        @api_client = RecordingStudioApi::ApiClient
          .includes(:credentials, access_recording: [:recordable, { parent_recording: :parent_recording }])
          .where(id: visible_api_client_ids)
          .find(params[:id])

        @access_recording = @api_client.access_recording
        @root_recording = @access_recording&.root_recording
        @can_manage_access_request = api_client_management_policy.manage?(@api_client)
        @latest_credential = @api_client.credentials.max_by { |credential| [credential.created_at.to_i, credential.id.to_i] }
        @rotated_credential_rows = rotated_credential_rows_for(@api_client.credentials, @latest_credential)
      rescue ActiveRecord::RecordNotFound
        head :not_found
      end

      def rotated_credential_rows_for(credentials, latest_credential)
        credentials
          .reject { |credential| credential.id == latest_credential&.id }
          .sort_by { |credential| [credential.created_at.to_i, credential.id.to_s] }
          .reverse
          .map { |credential| rotated_credential_row(credential) }
      end

      def rotated_credential_row(credential)
        {
          api_key: credential.oauth_client_id,
          status_text: credential_status_label(credential),
          status_style: credential_status_style(credential),
          last_used_at: credential.last_used_at,
          revoked_at: credential.revoked_at,
          expires_at: expires_at_for(credential),
          expires_text: expires_text_for(credential)
        }
      end

      def credential_status_style(credential)
        return :danger if credential.revoked_at.present?
        return :default if credential.expires_at.present? && credential.expires_at.past?

        :success
      end

      def expires_at_for(credential)
        return if credential.expires_at.blank? || credential.expires_at.past?

        credential.expires_at
      end

      def expires_text_for(credential)
        return "Expired" if credential.expires_at.present? && credential.expires_at.past?
        return "Never" if credential.expires_at.blank?

        credential.expires_at.to_date.to_s
      end

      def persist_access_updates(expires_at)
        return false unless access_management_policy.can_assign_role?(selected_edit_access_point_recording, @form_values.fetch(:role))

        failure = nil
        ActiveRecord::Base.transaction do
          failure = apply_access_grant_changes!
          raise ActiveRecord::Rollback unless failure.nil?

          update_api_client_name!
          update_latest_credential_expiry!(expires_at)
        end

        return true if failure.nil?

        @errors << failure
        false
      rescue RecordingStudioAccessible::GrantRefused, ActiveRecord::ActiveRecordError => e
        @errors << e.message
        false
      end

      def apply_access_grant_changes!
        return if @access_recording.nil?

        role = @form_values.fetch(:role)
        access_point_recording_id = @form_values.fetch(:access_point_recording_id)
        return move_access_point!(access_point_recording_id, role) if moving_access_point?(access_point_recording_id)
        return unless access_role_changing?(role)

        change_access_role!(role)
      end

      # Grant before revoke. The API client recording can only sit under an
      # Access recording, and revoke destroys the old one. A refused grant
      # never revokes. A refused revoke rolls the grant back with the transaction.
      def move_access_point!(access_point_recording_id, role)
        old_access = @access_recording
        new_parent = selected_edit_access_point_recording
        actor = access_actor(old_access)
        return "Access point is invalid" if new_parent.nil? || new_parent.id != access_point_recording_id
        return "Access actor is missing" if actor.nil?

        granted = RecordingStudioAccessible::Services::GrantRecordingAccess.call(
          recording: new_parent,
          actor: actor,
          role: role,
          manager_actor: current_request_actor
        )
        return granted.error.to_s if granted.failure?

        new_access = granted.value
        reparent_access_children!(old_access, new_access)
        relink_api_client!(old_access, new_access)

        revoked = RecordingStudioAccessible::Services::RevokeRecordingAccess.call(
          recording: old_access.parent_recording,
          access_recording: old_access,
          manager_actor: current_request_actor
        )
        return revoked.error.to_s if revoked.failure?

        nil
      end

      def change_access_role!(role)
        result = RecordingStudioAccessible::Services::UpdateRecordingAccess.call(
          recording: @access_recording.parent_recording,
          access_recording: @access_recording,
          role: role,
          manager_actor: current_request_actor
        )
        return if result.success?

        result.error.to_s
      end

      def moving_access_point?(access_point_recording_id)
        access_point_recording_id.present? && @access_recording.parent_recording_id != access_point_recording_id
      end

      def access_role_changing?(role)
        record = @access_recording.recordable
        return false unless record.respond_to?(:has_attribute?) && record.has_attribute?(:role)

        record.role.to_s != role.to_s
      end

      def access_actor(access_recording)
        record = access_recording.recordable
        record.actor if record.respond_to?(:actor)
      end

      def reparent_access_children!(old_access, new_access)
        RecordingStudio::Recording.unscoped.where(parent_recording_id: old_access.id).find_each do |child|
          child.update!(parent_recording: new_access)
        end
      end

      def relink_api_client!(old_access, new_access)
        now = Time.current
        updated_clients = RecordingStudioApi::ApiClient.where(id: @api_client.id).update_all(
          access_recording_id: new_access.id,
          updated_at: now
        )
        raise ActiveRecord::ActiveRecordError, "API client update failed" unless updated_clients == 1

        RecordingStudioApi::ApiCredential.where(api_client_id: @api_client.id, access_recording_id: old_access.id).update_all(
          access_recording_id: new_access.id,
          updated_at: now
        )
      end

      def update_api_client_name!
        updated_clients = RecordingStudioApi::ApiClient.where(id: @api_client.id).update_all(
          name: @form_values.fetch(:api_client_name),
          updated_at: Time.current
        )
        raise ActiveRecord::ActiveRecordError, "API client update failed" unless updated_clients == 1
      end

      def update_latest_credential_expiry!(expires_at)
        return if @latest_credential.blank?

        updated_credentials = RecordingStudioApi::ApiCredential.where(id: @latest_credential.id).update_all(
          expires_at: expires_at,
          updated_at: Time.current
        )
        raise ActiveRecord::ActiveRecordError, "Credential update failed" unless updated_credentials == 1
      end
    end
  end
end
