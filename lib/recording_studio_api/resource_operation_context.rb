# frozen_string_literal: true

module RecordingStudioApi
  ResourceOperationContext = Data.define(
    :recording,
    :recordable_type,
    :resource_name,
    :api_client,
    :credential,
    :access_recording,
    :access_grant,
    :root_recording,
    :params,
    :scoped_recordings
  )
end