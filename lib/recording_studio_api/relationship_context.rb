# frozen_string_literal: true
# lib/recording_studio_api/relationship_context.rb

module RecordingStudioApi
  # Request-scoped relationship state. Child recordings are fetched once for all
  # parents in a collection; custom relationship resolvers deliberately remain
  # host-owned because their data source is application-specific.
  class RelationshipContext
    ALL_REQUESTED = "*"

    attr_reader :scoped_recordings

    def self.for(recordings:, include_values:, scoped_recordings:, api:, version:, nested: false)
      new(
        recordings: recordings,
        include_values: include_values,
        scoped_recordings: scoped_recordings,
        api: api,
        version: version,
        nested: nested
      )
    end

    def initialize(recordings:, include_values:, scoped_recordings:, api:, version:, nested: false)
      @requested_relationships = parse_include_values(include_values)
      @scoped_recordings = scoped_recordings
      @api = api
      @version = version
      @nested = nested
      @children_by_parent_and_relationship = {}
      load_children(recordings) unless nested
    end

    def include?(name, definition)
      return false if @nested
      return true if definition.fetch(:include) == true

      definition.fetch(:include) == :request && requested?(name)
    end

    def relationship_value(recording, name, definition)
      case definition.fetch(:source)
      when :children
        children_for(recording, name)
      when :custom
        resolve_custom_relationship(recording, name, definition)
      end
    end

    def nested
      self.class.for(
        recordings: [],
        include_values: [],
        scoped_recordings: @scoped_recordings,
        api: @api,
        version: @version,
        nested: true
      )
    end

    private

    def parse_include_values(values)
      Array(values).flat_map do |value|
        case value
        when true, :request, "true", "request"
          ALL_REQUESTED
        when String
          value.split(",").map(&:strip).reject(&:blank?)
        else
          value.to_s.presence
        end
      end.compact.uniq
    end

    def requested?(name)
      @requested_relationships.include?(ALL_REQUESTED) || @requested_relationships.include?(name.to_s)
    end

    def load_children(recordings)
      parents = Array(recordings)
      return if parents.empty?

      definitions_by_parent_id = parents.each_with_object({}) do |parent, output|
        registration = RecordingStudioApi.recordable_registration_for(parent.recordable_type, api: @api)
        eligible_relationships = registration&.relationships&.select do |name, definition|
          definition.fetch(:source) == :children && include?(name, definition)
        end
        output[parent.id] = eligible_relationships if eligible_relationships.present?
      end
      parent_ids = definitions_by_parent_id.keys
      return if parent_ids.empty?

      rows = @scoped_recordings.where(parent_recording_id: parent_ids).to_a.group_by(&:parent_recording_id)
      definitions_by_parent_id.each do |parent_id, definitions|
        definitions.each do |name, definition|
          types = definition.fetch(:types)
          @children_by_parent_and_relationship[[parent_id, name]] = rows.fetch(parent_id, []).select do |child|
            types.empty? || types.include?(child.recordable_type)
          end
        end
      end
    end

    def children_for(recording, name)
      @children_by_parent_and_relationship.fetch([recording.id, name.to_s], [])
    end

    def resolve_custom_relationship(recording, _name, definition)
      resolver = definition[:resolver]
      value = if resolver.respond_to?(:call)
                call_resolver(resolver, recording.recordable)
              elsif recording.recordable.respond_to?(definition.fetch(:method))
                recording.recordable.public_send(definition.fetch(:method))
              end

      constrain_recordings_to_scope(normalize_collection(value))
    end

    def call_resolver(resolver, recordable)
      resolver.call(recordable, context: self)
    rescue ArgumentError
      resolver.call(recordable)
    end

    def constrain_recordings_to_scope(value)
      recordings = recording_values(value)
      return value if recordings.empty?

      allowed_ids = @scoped_recordings.where(id: recordings.map(&:id)).pluck(:id)
      filter_scoped_recordings(value, allowed_ids)
    end

    def recording_values(value)
      case value
      when Array
        value.select { |entry| recording?(entry) }
      else
        recording?(value) ? [value] : []
      end

      def normalize_collection(value)
        return value if value.is_a?(Array) || value.is_a?(Hash) || value.is_a?(String)
        return value.to_a if value.respond_to?(:to_a) && !recording?(value)

        value
      end
    end

    def filter_scoped_recordings(value, allowed_ids)
      if value.is_a?(Array)
        value.filter_map { |entry| recording?(entry) && !allowed_ids.include?(entry.id) ? nil : entry }
      elsif recording?(value) && !allowed_ids.include?(value.id)
        nil
      else
        value
      end
    end

    def recording?(value)
      value.respond_to?(:recordable_type) && value.respond_to?(:recordable) && value.respond_to?(:id)
    end
  end
end
