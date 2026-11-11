# frozen_string_literal: true

module RecordingStudioApi
  module RequestPayload
    module_function

    def call(context)
      request_params = context.request_params || context.params
      request_params.respond_to?(:to_unsafe_h) ? request_params.to_unsafe_h : request_params.to_h
    end
  end
end
