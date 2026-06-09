# frozen_string_literal: true

require_relative "action_registration"
require_relative "errors"

module RecordingStudioApi
  class ActionRegistry
    def initialize
      @registrations = {}
    end

    # rubocop:disable Metrics/ParameterLists
    def register(name, capability:, version: nil, version_notes: nil, deprecation: nil, http_verb: :post, handler:, serializer: nil, scope: :member, openapi: nil, input_contract: nil)
      registration = ActionRegistration.new(
        name: name,
        capability: capability,
        version: version,
        version_notes: version_notes,
        deprecation: deprecation,
        http_verb: http_verb,
        handler: handler,
        serializer: serializer,
        scope: scope,
        openapi: openapi,
        input_contract: input_contract
      )
      registration.validate!

      key = registration.name
      registrations = (@registrations[key] ||= [])
      raise ConfigurationError, "API action #{key} version #{registration.version} is already registered" if registrations.any? { |existing| existing.version == registration.version }

      registrations << registration
    end
    # rubocop:enable Metrics/ParameterLists

    def fetch(name, profile: nil)
      registration = resolve(name, profile: profile)
      return registration if registration

      raise KeyError, "key not found: #{name.inspect}"
    end

    def [](name)
      resolve(name)
    end

    def resolve(name, profile: nil)
      selected_registration(@registrations[name.to_s], profile: profile)
    end

    def available_for(recordable_type, scope: nil, profile: nil)
      selected_registrations(profile: profile).select do |registration|
        registration.applicable_to?(recordable_type) && (scope.nil? || registration.scope == scope.to_sym)
      end
    end

    def to_h
      @registrations.transform_values do |registrations|
        latest = selected_registration(registrations, profile: nil)
        latest.as_json.merge(versions: registrations.map { |registration| registration.version.to_s }.sort)
      end
    end

    def validate!
      @registrations.each_value do |registrations|
        registrations.each(&:validate!)
      end
    end

    private

    def selected_registrations(profile: nil)
      @registrations.values.filter_map do |registrations|
        selected_registration(registrations, profile: profile)
      end
    end

    def selected_registration(registrations, profile:)
      candidates = Array(registrations)
      return if candidates.empty?

      candidates = candidates.select { |registration| profile.matches?(registration) } if profile
      candidates.max_by(&:version)
    end
  end
end
