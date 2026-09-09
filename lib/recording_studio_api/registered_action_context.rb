# frozen_string_literal: true

module RecordingStudioApi
  RegisteredActionContext = Data.define(
    :api_client,
    :credential,
    :access_recording,
    :access_grant,
    :root_recording,
    :params
  ) do
    def api_key
      api_client&.api_key.presence || "public"
    end
  end
end
