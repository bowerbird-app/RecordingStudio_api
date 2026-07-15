# frozen_string_literal: true

require "rubygems/requirement"

module RecordingStudioApi
  class ApiVersionProfile
    attr_reader :name, :requirements

    def initialize(name)
      @name = name.to_s
      @requirements = {}
    end

    def use(contribution, requirement = nil)
      key = normalize_contribution(contribution)
      @requirements[key] = normalize_requirement(contribution, requirement)
    end

    def matches?(registration)
      requirement = requirement_for(registration)
      return true if requirement.nil?

      requirement.satisfied_by?(registration.version)
    end

    def requirement_for(registration)
      registration.contribution_keys.lazy.filter_map { |key| requirements[key] }.first
    end

    def as_json(*)
      {
        name: name,
        requirements: requirements.transform_values(&:to_s)
      }
    end

    private

    def normalize_contribution(value)
      normalized = value.to_s.strip
      raise ConfigurationError, "API contribution name is required for #{name}" if normalized.empty?

      normalized.to_sym
    end

    def normalize_requirement(contribution, value)
      return Gem::Requirement.default if value.nil? || value.to_s.strip.empty?

      Gem::Requirement.new(*Array(value))
    rescue ArgumentError => e
      raise ConfigurationError, "Invalid API contribution requirement for #{contribution}: #{e.message}"
    end
  end
end