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
        now = Time.current
        access_record = @access_recording&.recordable
        access_point_recording_id = @form_values.fetch(:access_point_recording_id)
        return false unless access_management_policy.can_assign_role?(selected_edit_access_point_recording, @form_values.fetch(:role))

        ActiveRecord::Base.transaction do
          if access_point_recording_id.present? && @access_recording.parent_recording_id != access_point_recording_id
            updated_access_recordings = RecordingStudio::Recording.unscoped.where(id: @access_recording.id).update_all(
              parent_recording_id: access_point_recording_id,
              updated_at: now
            )

            raise ActiveRecord::ActiveRecordError, "Access recording update failed" unless updated_access_recordings == 1
          end

          if access_record.respond_to?(:id) && access_record.respond_to?(:has_attribute?) && access_record.has_attribute?(:role)
            update_attributes = { role: @form_values.fetch(:role) }
            update_attributes[:updated_at] = now if access_record.has_attribute?(:updated_at)

            updated_access_records = access_record.class.where(id: access_record.id).update_all(update_attributes)

            raise ActiveRecord::ActiveRecordError, "Access update failed" unless updated_access_records == 1
          end

          updated_clients = RecordingStudioApi::ApiClient.where(id: @api_client.id).update_all(
            name: @form_values.fetch(:api_client_name),
            updated_at: now
          )

          raise ActiveRecord::ActiveRecordError, "API client update failed" unless updated_clients == 1

          if @latest_credential.present?
            updated_credentials = RecordingStudioApi::ApiCredential.where(id: @latest_credential.id).update_all(
              expires_at: expires_at,
              updated_at: now
            )

            raise ActiveRecord::ActiveRecordError, "Credential update failed" unless updated_credentials == 1
          end
        end

        true
      rescue ActiveRecord::ActiveRecordError
        false
      end
    end
  end
end
