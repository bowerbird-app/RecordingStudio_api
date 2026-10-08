# frozen_string_literal: true

module RecordingStudioApi
  ActionContext = Data.define(
    :recording,
    :api_client,
    :credential,
    :access_recording,
    :access_grant,
    :root_recording,
    :params,
    :progress_reporter,
    :id,
    :recordable_type
  ) do
    include ProgressReporting

    def initialize(
      recording:,
      api_client:,
      credential:,
      access_recording:,
      access_grant:,
      root_recording:,
      params:,
      progress_reporter: nil,
      id: nil,
      recordable_type: nil
    )
      super
    end

    def api_key
      api_client&.api_key.presence || "public"
    end

    def actor
      access_grant&.actor
    end
  end
end
