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
    :api_version,
    :params,
    :request_params,
    :scoped_recordings,
    :parent_recording,
    :idempotency_key
  ) do
    def initialize( # rubocop:disable Metrics/ParameterLists
      recording:,
      recordable_type:,
      resource_name:,
      api_client:,
      credential:,
      access_recording:,
      access_grant:,
      root_recording:,
      api_version:,
      params:,
      request_params:,
      scoped_recordings:,
      parent_recording:,
      idempotency_key: nil
    )
      super
    end

    def api_key
      api_client&.api_key.presence || "public"
    end
  end
end
