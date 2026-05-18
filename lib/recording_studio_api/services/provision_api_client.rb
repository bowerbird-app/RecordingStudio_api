# frozen_string_literal: true

module RecordingStudioApi
  module Services
    class ProvisionApiClient < BaseService
      def initialize(access_recording:, name:, expires_at: nil)
        @access_recording = access_recording
        @name = name
        @expires_at = expires_at
      end

      private

      attr_reader :access_recording, :name, :expires_at

      def perform
        return failure("Access recording is required") if access_recording.nil?
        return failure("API client name is required") if name.blank?
        return failure("Access recording must point to RecordingStudio::Access") unless access_recording.recordable_type == "RecordingStudio::Access"

        token = Token.generate
        payload = nil

        ApiCredential.transaction do
          revoke_existing_credentials!

          api_client = ApiClient.create!(name: name, access_recording: access_recording)
          recording = RecordingStudio.record!(
            action: "created",
            recordable: api_client,
            root_recording: access_recording.root_recording,
            parent_recording: access_recording,
            actor: api_client
          ).recording

          credential = ApiCredential.create!(
            api_client: api_client,
            access_recording: access_recording,
            token_public_id: token.fetch(:public_id),
            token_digest: token.fetch(:digest),
            token_prefix: token.fetch(:prefix),
            expires_at: expires_at
          )

          payload = {
            api_client: api_client,
            credential: credential,
            recording: recording,
            token: token.fetch(:token)
          }
        end

        success(payload)
      rescue ActiveRecord::ActiveRecordError, RecordingStudioApi::Error => e
        failure(e)
      end

      def revoke_existing_credentials!
        ApiCredential.active.where(access_recording: access_recording).find_each do |credential|
          credential.revoke!
        end
      end

      def service_args
        { access_recording_id: access_recording&.id, name: name, expires_at: expires_at }
      end
    end
  end
end
