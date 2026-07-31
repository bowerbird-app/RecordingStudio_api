# frozen_string_literal: true

module RecordingStudioApi
  AuthenticatedClient = Data.define(
    :api_client,
    :credential,
    :access_recording,
    :root_recording,
    :api_key
  )
end
