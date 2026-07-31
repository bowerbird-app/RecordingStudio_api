# frozen_string_literal: true

module RecordingStudioApi
  module Services
    class RevokeTestCredential < BaseService
      def initialize(api:, credential_id:, access_token_id:)
        @api_key = RecordingStudioApi.configuration.fetch_api(api).name
        @credential_id = credential_id
        @access_token_id = access_token_id
      end

      private

      attr_reader :api_key, :credential_id, :access_token_id

      def perform
        credential = ApiCredential.joins(:api_client).find_by(
          id: credential_id,
          recording_studio_api_api_clients: { api_key: api_key }
        )
        return failure("Test credential was not found for the selected API") if credential.nil?

        access_token = credential.access_tokens.find_by(id: access_token_id)
        return failure("Test access token was not found for the selected credential") if access_token.nil?

        revoked_at = Time.current
        ApiCredential.transaction do
          access_token.revoke!(time: revoked_at) if access_token.revoked_at.nil?
          credential.revoke!(time: revoked_at) if credential.revoked_at.nil?
        end

        success(credential: credential, access_token: access_token)
      rescue ActiveRecord::ActiveRecordError => e
        failure(e.message)
      end
    end
  end
end