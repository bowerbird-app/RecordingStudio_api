# frozen_string_literal: true

module RecordingStudioApi
  module Services
    class VoidOauthAuthorization < BaseService
      def initialize(authorization:, time: nil)
        @authorization = authorization
        @time = time
      end

      private

      attr_reader :authorization

      def perform
        return success(authorization) if authorization.nil?
        return success(authorization) if authorization.revoked? && authorization.access_recording&.trashed_at.present?

        OauthAuthorization.transaction do
          authorization.lock!
          time = @time || Time.current
          authorization.update_columns(revoked_at: time, updated_at: time) unless authorization.revoked?

          trash_granted_access!(time)
          revoke_tokens!(time)
        end

        authorization.reload
        success(authorization)
      rescue ActiveRecord::ActiveRecordError => e
        failure(e)
      end

      def trash_granted_access!(time)
        access_recording = authorization.access_recording
        return if access_recording.nil?
        return if access_recording.trashed_at.present?

        access_recording.update_columns(trashed_at: time, updated_at: time)
      end

      def revoke_tokens!(time)
        ApiAccessToken.where(oauth_authorization_id: authorization.id, revoked_at: nil)
                      .update_all(revoked_at: time, updated_at: time)
        OauthRefreshToken.where(oauth_authorization_id: authorization.id, revoked_at: nil)
                         .update_all(revoked_at: time, updated_at: time)
      end

      def service_args
        { authorization_id: authorization&.id }
      end
    end
  end
end
