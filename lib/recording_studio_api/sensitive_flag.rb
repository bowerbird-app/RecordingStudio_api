# frozen_string_literal: true

module RecordingStudioApi
  module SensitiveFlag
    module_function

    def default?(api)
      RecordingStudioApi.configuration.canonical_api_name(api) != "public"
    end

    def coerce(value, api:)
      return default?(api) if value.nil?

      boolean!(value)
    end

    def boolean!(value, name: nil)
      return value if [true, false].include?(value)

      suffix = name ? " for #{name}" : ""
      raise ConfigurationError, "sensitive must be true or false#{suffix}"
    end
  end
end
