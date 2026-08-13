# frozen_string_literal: true

module RecordingStudioApi
  class RelationshipContext
    INCLUDE_NAME_PATTERN = /\A[a-zA-Z_][a-zA-Z0-9_]*\z/

    attr_reader :access_grant, :api_key, :api_version, :params, :scoped_recordings, :selected_include_names

    def self.for(recordings:, include_values:, scoped_recordings:, api_key:, api_version:, access_grant: nil, params: {}, nested: false, batch: false)
      new(
        recordings: recordings,
        include_values: include_values,
        scoped_recordings: scoped_recordings,
        api_key: api_key,
        api_version: api_version,
        access_grant: access_grant,
        params: params,
        nested: nested,
        batch: batch
      )
    end

    def initialize(recordings:, include_values:, scoped_recordings:, api_key:, api_version:, access_grant: nil, params: {}, nested: false, batch: false)
      @recordings = Array(recordings)
      @scoped_recordings = scoped_recordings
      @api_key = api_key
      @api_version = api_version
      @access_grant = access_grant
      @params = if params.respond_to?(:to_unsafe_h)
                  params.to_unsafe_h
                elsif params.respond_to?(:to_h)
                  params.to_h
                else
                  {}
                end
      @nested = nested
      @selected_include_names = nested ? [].freeze : select_include_names(include_values)
      @prepared_relationships = batch && !nested ? RelationshipBatchLoader.new(context: self, entries: selected_relationship_entries).call : {}
      @resolved_relationship_metadata = {}
    end

    def include?(name, definition)
      !@nested && selected_include_names.include?(name.to_s) && [true, :request].include?(definition.include)
    end

    def relationship_value(recording, name, definition = nil)
      prepared = @prepared_relationships[[recording.id, name.to_s]]
      return prepared.fetch(:value) if prepared

      definition ||= relationship_definition(recording, name)
      return nil unless definition

      authorize_relationship!(recording, name, definition)

      case definition.source
      when :children then resolve_children(recording, name, definition)
      when :custom then resolve_custom_relationship(recording, name, definition)
      else raise ConfigurationError, "Relationship #{name} has an unsupported source"
      end
    end

    def relationship_metadata(recording, name)
      @prepared_relationships.dig([recording.id, name.to_s], :meta) ||
        @resolved_relationship_metadata[[recording.id, name.to_s]]
    end

    def nested
      self.class.for(
        recordings: [], include_values: nil, scoped_recordings: scoped_recordings,
        api_key: api_key, api_version: api_version, access_grant: access_grant, params: params, nested: true, batch: false
      )
    end

    def authorize_relationship!(recording, name, definition)
      authorize!(resolver_context(recording, definition, name: name), name)
    end

    def authorized_targets(targets, recording, name, definition)
      authorize_targets!(targets, recording, name, definition)
      targets
    end

    def normalize_custom_value(value, recording, name, definition)
      authorize_relationship!(recording, name, definition)
      targets = normalize_custom_targets(value, name, definition)
      authorized_targets(targets_in_scope(targets), recording, name, definition).then do |authorized|
        definition.many ? authorized : authorized.first
      end
    end

    def resolver_context(recording, definition, name:, target_recording: nil)
      registration = RecordingStudioApi.recordable_registration_for(recording.recordable_type, api: api_key)
      SerializerContext.build(
        recording: recording, context: self, api_version: api_version, api_key: api_key,
        registration: registration, relationship: definition
      ).with(target_recording: target_recording)
    end

    def collection?(value)
      !value.is_a?(String) && !value.is_a?(Hash) && value.respond_to?(:to_a)
    end

    def recording?(value)
      defined?(RecordingStudio::Recording) && value.is_a?(RecordingStudio::Recording)
    end

    private

    def select_include_names(include_values)
      definitions = selectable_definitions
      always_included = definitions.select { |_name, definition| definition.include == true }.keys
      requested = parse_include_values(include_values)
      requested.each do |name|
        definition = definitions[name]
        raise_invalid_include!("unknown name #{name}") unless definition
        raise_invalid_include!("name #{name} cannot be requested") unless [true, :request].include?(definition.include)
      end
      (always_included + requested).uniq.freeze
    end

    def selectable_definitions
      @recordings.each_with_object({}) do |recording, definitions|
        registration = RecordingStudioApi.recordable_registration_for(recording.recordable_type, api: api_key)
        next unless registration

        registration.fields.each { |name, definition| definitions[name.to_s] ||= definition }
        registration.relationships.each { |name, definition| definitions[name.to_s] ||= definition }
      end
    end

    def parse_include_values(value)
      return [] if value.nil?
      raise_invalid_include!("must be one comma-separated string") unless value.is_a?(String)

      names = value.split(",", -1)
      raise_invalid_include!("values cannot be blank") if names.any?(&:blank?)
      names.each { |name| raise_invalid_include!("value #{name.inspect} is invalid") unless name.match?(INCLUDE_NAME_PATTERN) }
      duplicate = names.group_by(&:itself).find { |_name, occurrences| occurrences.length > 1 }&.first
      raise_invalid_include!("value #{duplicate.inspect} is duplicated") if duplicate
      names
    end

    def selected_relationship_entries
      @recordings.flat_map do |recording|
        registration = RecordingStudioApi.recordable_registration_for(recording.recordable_type, api: api_key)
        next [] unless registration

        registration.relationships.filter_map do |name, definition|
          [recording, name, definition] if include?(name, definition)
        end
      end
    end

    def relationship_definition(recording, name)
      RecordingStudioApi.recordable_registration_for(recording.recordable_type, api: api_key)&.relationships&.fetch(name.to_s, nil)
    end

    def resolve_children(recording, name, definition)
      scope = scoped_recordings.where(parent_recording_id: recording.id, recordable_type: definition.child_type)
      scope = scope.reorder(direct_child_order(definition))
      children = scope.limit(definition.many ? definition.limit + 1 : 1).preload(:recordable).to_a
      authorize_targets!(children, recording, name, definition)
      return children.first unless definition.many

      @resolved_relationship_metadata[[recording.id, name.to_s]] = { limit: definition.limit, has_more: true } if children.length > definition.limit
      children.first(definition.limit)
    end

    def direct_child_order(definition)
      order = definition.order
      order = { "created_at" => :asc } if order.empty?
      order = order.merge("id" => :asc) unless order.key?("id")
      order
    end

    def resolve_custom_relationship(recording, name, definition)
      value = definition.resolver.call(resolver_context(recording, definition, name: name))
      normalize_custom_value(value, recording, name, definition)
    end

    def normalize_custom_targets(value, name, definition)
      return [] if value.nil?
      if definition.many
        raise_invalid_target!(name, "must return a collection of recordings") unless collection?(value)

        targets = value.to_a
        raise_invalid_target!(name, "contains a non-recording target") unless targets.all? { |target| recording?(target) }
        targets
      else
        raise_invalid_target!(name, "must return one recording") unless recording?(value)

        [value]
      end
    end

    def targets_in_scope(targets)
      return [] if targets.empty?

      allowed_ids = scoped_recordings.where(id: targets.map(&:id)).pluck(:id)
      targets.select { |target| allowed_ids.include?(target.id) }
    end

    def authorize_targets!(targets, recording, name, definition)
      targets.each { |target| authorize!(resolver_context(recording, definition, name: name, target_recording: target), name) }
    end

    def authorize!(context, name)
      raise AuthorizationError, "Cannot authorize relationship #{name} without an access grant" unless access_grant
      return unless context.current_relationship.authorize

      raise AuthorizationError, "Not authorized to read relationship #{name}" unless context.current_relationship.authorize.call(context) == true
    rescue AuthorizationError
      raise
    rescue StandardError
      raise AuthorizationError, "Not authorized to read relationship #{name}"
    end

    def raise_invalid_include!(message)
      raise InvalidActionInputError, "include #{message}"
    end

    def raise_invalid_target!(name, message)
      raise InvalidActionInputError, "relationship #{name} #{message}"
    end
  end
end
