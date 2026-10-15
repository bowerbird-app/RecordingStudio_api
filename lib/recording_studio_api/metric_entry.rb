# frozen_string_literal: true

module RecordingStudioApi
  class MetricEntry
    attr_reader :name, :description, :parameters

    def initialize(name:, description:, parameters:)
      @name = name.to_s.freeze
      @description = description&.freeze
      @parameters = parameters.map { |parameter| deep_freeze(parameter) }.freeze
      freeze
    end

    def as_json(*)
      { name: name, description: description, parameters: parameters }
    end

    private

    def deep_freeze(value)
      case value
      when Hash
        value.transform_values { |child| deep_freeze(child) }.freeze
      when Array
        value.map { |child| deep_freeze(child) }.freeze
      when String
        value.freeze
      else
        value
      end
    end
  end
end
