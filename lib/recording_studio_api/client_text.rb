# frozen_string_literal: true

module RecordingStudioApi
  module ClientText
    MAX_LENGTH = 80

    module_function

    def cap(value)
      text = value.to_s.gsub(/[[:cntrl:]]/, "")
      return text if text.length <= MAX_LENGTH

      "#{text[0, MAX_LENGTH]}..."
    end
  end
end
