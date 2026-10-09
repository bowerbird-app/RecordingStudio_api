# frozen_string_literal: true

require_relative "errors"

module RecordingStudioApi
  module UiWidgetId
    module_function

    def normalize(value, name:)
      return if value.nil?
      unless value.is_a?(String) || value.is_a?(Symbol)
        raise ConfigurationError, "ui must be a string widget id for #{name}"
      end

      normalized = value.to_s.strip
      raise ConfigurationError, "ui must be a string widget id for #{name}" if normalized.empty?

      normalized
    end
  end
end
