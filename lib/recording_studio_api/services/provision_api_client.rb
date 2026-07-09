# frozen_string_literal: true

require "securerandom"

module RecordingStudioApi
  module Services
    class ProvisionApiClient < BaseService
      def initialize(name:, access_recording: nil, access_point_recording: nil, manager_actor: nil, role: nil, expires_at: nil)
        @access_recording = access_recording
        @access_point_recording = access_point_recording
        @manager_actor = manager_actor
        @role = role
        @name = name
        @expires_at = expires_at
      end

      private

      attr_reader :access_recording, :access_point_recording, :manager_actor, :role, :name, :expires_at

      def perform
        return failure("Access point recording is required") if resolved_access_point_recording.nil?
        return failure("Manager actor is required") if resolved_manager_actor.nil?
        return failure("Access role is required") if resolved_role.blank?
        return failure("API client name is required") if name.blank?
        return failure("Access recording must point to RecordingStudio::Access") if access_recording.present? && access_recording.recordable_type != "RecordingStudio::Access"

        token = Token.generate
        payload = nil

        ApiCredential.transaction do
          api_client = ApiClient.new(id: SecureRandom.uuid, name: name)
          client_access_recording = create_client_access_recording!(api_client)
          api_client.access_recording = client_access_recording
          api_client.save!

          recording = RecordingStudio.record!(
            action: "created",
            recordable: api_client,
            root_recording: client_access_recording.root_recording,
            parent_recording: client_access_recording,
            actor: api_client
          ).recording

          credential = ApiCredential.create!(
            api_client: api_client,
            access_recording: client_access_recording,
            token_public_id: token.fetch(:public_id),
            token_digest: token.fetch(:digest),
            token_prefix: token.fetch(:prefix),
            expires_at: resolved_expiry
          )

          RecordingStudio.record!(
            action: "created",
            recordable: credential,
            root_recording: recording.root_recording,
            parent_recording: recording,
            actor: api_client
          )

          payload = {
            api_client: api_client,
            credential: credential,
            recording: recording,
            access_recording: client_access_recording,
            token: token.fetch(:token)
          }
        end

        success(payload)
      rescue ActiveRecord::ActiveRecordError, RecordingStudioApi::Error => e
        failure(e)
      end

      def create_client_access_recording!(api_client)
        result = RecordingStudioAccessible.grant_access(
          recording: resolved_access_point_recording,
          actor: api_client,
          role: resolved_role,
          manager_actor: resolved_manager_actor
        )

        raise RecordingStudioApi::Error, result.error if result.failure?

        result.value
      end

      def resolved_access_point_recording
        @resolved_access_point_recording ||= access_point_recording || access_recording&.parent_recording || access_recording&.root_recording
      end

      def resolved_manager_actor
        @resolved_manager_actor ||= manager_actor || access_recording&.recordable&.try(:actor)
      end

      def resolved_role
        @resolved_role ||= role.to_s.presence || access_recording&.recordable&.try(:role).to_s.presence
      end

      def service_args
        {
          access_recording_id: access_recording&.id,
          access_point_recording_id: access_point_recording&.id,
          manager_actor_id: manager_actor&.id,
          manager_actor_type: manager_actor&.class&.name,
          role: role,
          name: name,
          expires_at: expires_at
        }
      end

      def resolved_expiry
        return expires_at if expires_at.present?

        ttl = RecordingStudioApi.configuration.credential_ttl
        ttl.present? ? Time.current + ttl : nil
      end
    end
  end
end
