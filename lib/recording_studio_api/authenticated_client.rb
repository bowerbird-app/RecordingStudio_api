# frozen_string_literal: true

module RecordingStudioApi
  AuthenticatedClient = Data.define(
    :api_client,
    :credential,
    :access_recording,
    :scope_recording,
    :root_recording
  )
end
