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
          failure = apply_access_grant_changes!(expires_at)
          raise ActiveRecord::Rollback unless failure.nil?

          unless @replacement_payload
            update_api_client_name!
            update_latest_credential_expiry!(expires_at)
          end
        end

        return true if failure.nil?

        @errors << failure
        false
      rescue RecordingStudioAccessible::GrantRefused, ActiveRecord::ActiveRecordError => e
        @errors << e.message
        false
      end

      def apply_access_grant_changes!(expires_at)
        return if @access_recording.nil?

        role = @form_values.fetch(:role)
        access_point_recording_id = @form_values.fetch(:access_point_recording_id)
        return replace_client_at_access_point!(access_point_recording_id, role, expires_at) if moving_access_point?(access_point_recording_id)
        return unless access_role_changing?(role)

        change_access_role!(role)
      end

      def replace_client_at_access_point!(access_point_recording_id, role, expires_at)
        new_parent = selected_edit_access_point_recording
        return "Access point is invalid" if new_parent.nil? || new_parent.id != access_point_recording_id

        result = RecordingStudioApi::Services::ProvisionApiClient.call(
          access_point_recording: new_parent,
          manager_actor: current_request_actor,
          role: role,
          name: @form_values.fetch(:api_client_name),
          expires_at: expires_at,
          api: @api_client.api_key
        )
        return result.error.to_s if result.failure?

        apply_credential_expiry!(result.value.fetch(:credential), expires_at)
        retire_api_client!(@api_client)
        remove_access_children!(@access_recording)
        revoked = RecordingStudioAccessible::Services::RevokeRecordingAccess.call(
          recording: @access_recording.parent_recording,
          access_recording: @access_recording,
          manager_actor: current_request_actor
        )
        return revoked.error.to_s if revoked.failure?

        @replacement_payload = result.value
        nil
      end

      def remove_access_children!(access_recording)
        RecordingStudio::Recording.unscoped.where(parent_recording_id: access_recording.id).find_each do |child|
          remove_access_children!(child)
          child.destroy!
        end
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

      def retire_api_client!(api_client)
        api_client.credentials.find_each do |credential|
          if credential.revoked_at.nil?
            credential.revoke!
          else
            credential.revoke_outstanding_access_tokens!
          end
        end
      end

      def apply_credential_expiry!(credential, expires_at)
        updated_credentials = RecordingStudioApi::ApiCredential.where(id: credential.id).update_all(
          expires_at: expires_at,
          updated_at: Time.current
        )
        raise ActiveRecord::ActiveRecordError, "Credential update failed" unless updated_credentials == 1
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

        apply_credential_expiry!(@latest_credential, expires_at)
      end
    end
  end
end
