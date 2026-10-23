# frozen_string_literal: true

module RecordingStudioApi
  AuthenticatedClient = Data.define(
    :api_client,
    :credential,
    :access_recording,
    :root_recording,
    :api_key,
    :authorized_by
  ) do
    def initialize(api_client:, credential:, access_recording:, root_recording:, api_key:, authorized_by: nil)
      super
    end
  end
end
