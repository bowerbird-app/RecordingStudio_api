# frozen_string_literal: true

module RecordingStudioApi
  ActionContext = Data.define(
    :recording,
    :api_client,
    :credential,
    :access_recording,
    :access_grant,
    :root_recording,
    :params
  )
end
