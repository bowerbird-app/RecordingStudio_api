# frozen_string_literal: true

module RecordingStudioApi
  class MetricEntry
    attr_reader :name, :description, :parameters, :unit, :title, :timezone, :freshness

    def initialize(name:, description:, parameters:, unit:, title:, timezone:, freshness:)
      @name = name.to_s.freeze
      @description = description&.freeze
      @parameters = parameters.map { |parameter| deep_freeze(parameter) }.freeze
      @unit = unit&.to_s&.freeze
      @title = title.to_s.freeze
      @timezone = timezone.to_s.freeze
      @freshness = deep_freeze(freshness)
      freeze
    end

    def as_json(*)
      {
        name: name,
        description: description,
        unit: unit,
        title: title,
        timezone: timezone,
        freshness: freshness,
        parameters: parameters
      }
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
