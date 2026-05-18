# frozen_string_literal: true

module RecordingStudioApi
  module Concerns
    module BearerAuthentication
      extend ActiveSupport::Concern

      included do
        before_action :authenticate_api_client!
      end

      private

      attr_reader :current_api_client,
                  :current_api_credential,
                  :current_access_recording,
                  :current_root_recording

      def authenticate_api_client!
        result = RecordingStudioApi::Services::AuthenticateBearerToken.call(
          authorization_header: request.headers["Authorization"]
        )
        raise AuthenticationError, result.error if result.failure?

        authenticated_client = result.value
        @current_api_client = authenticated_client.api_client
        @current_api_credential = authenticated_client.credential
        @current_access_recording = authenticated_client.access_recording
        @current_root_recording = authenticated_client.root_recording
      end
    end
  end
end
