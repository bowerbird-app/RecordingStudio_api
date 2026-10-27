# frozen_string_literal: true

module RecordingStudioApi
  class Configuration
    module LayoutSetting
      def layout=(value)
        @layout = RecordingStudio::Layout.accept(value)
      end

      # Older initializers assign `layout_name`. A string, nil, or false is the
      # same setting as `layout`. Other values stay on `layout_name` only.
      def layout_name=(value)
        @layout_name = value
        case value
        when nil, false
          self.layout = value
        when String
          self.layout = value.strip.empty? ? nil : value
        end
      end

      private

      def exported_layout
        case layout
        when nil, false, String
          layout
        else
          :callable
        end
      end
    end
  end
end
