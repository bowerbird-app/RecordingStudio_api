# frozen_string_literal: true

require_relative "recordable_registration"
require_relative "errors"

module RecordingStudioApi
  class RecordableRegistry
    def initialize
      @registrations = {}
      @seen_since_reload = {}
      @reload_pending = false
      @mutex = Mutex.new
    end

    def self.profiles_for(api)
      profiles = api.api_version_profiles.values
      return [nil] if profiles.empty?

      uncovered = api.api_versions.any? { |version| api.api_version_profiles[version].nil? }
      uncovered ? profiles + [nil] : profiles
    end

    def register(recordable_type, serializer: nil, output_keys: nil, fields: nil, openapi: nil,
                 sortable_attributes: nil, writable_attributes: nil, immutable_fields: nil,
                 relationships: nil, immutable_relationships: nil, operations: nil, capability_actions: nil,
                 auto_capability_actions: nil, metrics: nil, public_name: nil, version: nil)
      incoming = RecordableRegistration.new(
        recordable_type: recordable_type, serializer: serializer, output_keys: output_keys, fields: fields,
        openapi: openapi, sortable_attributes: sortable_attributes, writable_attributes: writable_attributes,
        immutable_fields: immutable_fields, relationships: relationships,
        immutable_relationships: immutable_relationships, operations: operations,
        capability_actions: capability_actions, auto_capability_actions: auto_capability_actions, metrics: metrics,
        public_name: public_name, version: version
      )
      key = incoming.recordable_type
      @mutex.synchronize do
        replace_metrics = @reload_pending && !@seen_since_reload[key]
        @registrations[key] = merge_registrations(@registrations[key], incoming, replace_metrics: replace_metrics)
        @seen_since_reload[key] = true
      end
    end

    # The next registration of each type may replace its metric allowlist.
    # Development reload runs host registration again against the same registry.
    def prepare_for_reload!
      @mutex.synchronize do
        @reload_pending = true
        @seen_since_reload = {}
      end
    end

    def fetch(recordable_type)
      @mutex.synchronize { @registrations.fetch(recordable_type.to_s) }
    end

    def [](recordable_type)
      @mutex.synchronize { @registrations[recordable_type.to_s] }
    end

    def to_h
      @mutex.synchronize { @registrations.transform_values(&:as_json) }
    end

    def validate!(profiles: nil)
      registrations = @mutex.synchronize { @registrations.values }
      registrations.each(&:validate!)
      (profiles.nil? ? [nil] : profiles).each do |profile|
        assert_unique_public_names!(registrations, profile)
      end
    end

    def type_for_public_name(name, profile: nil)
      query = name.to_s.strip
      return if query.empty?

      selected = @mutex.synchronize { @registrations.values }.select { |registration| registration.selected_by?(profile) }
      by_name = selected.select { |registration| registration.public_name == query }
      if by_name.many?
        classes = by_name.map(&:recordable_type).sort
        raise ConfigurationError, "Public name #{query} clashes for #{classes.join(', ')}"
      end
      return by_name.first.recordable_type if by_name.one?

      match = selected.find { |registration| registration.recordable_type == query }
      return if match.nil?

      match.recordable_type
    end

    private

    def merge_registrations(existing, incoming, replace_metrics: false)
      return incoming unless existing

      @replace_metrics = replace_metrics
      RecordableRegistration.new(
        recordable_type: incoming.recordable_type,
        serializer: merge_value("serializer", existing.serializer, incoming.serializer),
        output_keys: existing.output_keys | incoming.output_keys,
        fields: merge_definitions("field", existing.fields, incoming.fields),
        openapi: deep_merge_hashes(existing.openapi, incoming.openapi),
        sortable_attributes: existing.sortable_attributes | incoming.sortable_attributes,
        writable_attributes: existing.writable_attributes | incoming.writable_attributes,
        immutable_fields: existing.immutable_fields | incoming.immutable_fields,
        relationships: merge_definitions("relationship", existing.relationships, incoming.relationships),
        immutable_relationships: existing.immutable_relationships | incoming.immutable_relationships,
        public_name: merged_public_name(existing, incoming),
        public_name_supplied: existing.public_name_supplied? || incoming.public_name_supplied?,
        version: merged_version(existing, incoming),
        version_supplied: existing.version_supplied? || incoming.version_supplied?,
        **merged_explicit_sets(existing, incoming)
      )
    end

    def merged_public_name(existing, incoming)
      clash = existing.public_name_supplied? && incoming.public_name_supplied? && existing.public_name != incoming.public_name
      raise ConfigurationError, "Public name cannot be redefined incompatibly for #{incoming.recordable_type}" if clash

      incoming.public_name_supplied? ? incoming.public_name : existing.public_name
    end

    def merged_version(existing, incoming)
      clash = existing.version_supplied? && incoming.version_supplied? && existing.version != incoming.version
      raise ConfigurationError, "Recordable version cannot be redefined incompatibly for #{incoming.recordable_type}" if clash

      incoming.version_supplied? ? incoming.version : existing.version
    end

    def assert_unique_public_names!(registrations, profile)
      selected = registrations.select { |registration| registration.selected_by?(profile) }
      selected.group_by(&:public_name).each do |public_name, group|
        next if group.size < 2

        classes = group.map(&:recordable_type).sort
        where = profile ? " on API version #{profile.name}" : ""
        raise ConfigurationError, "Public name #{public_name} clashes for #{classes.join(', ')}#{where}"
      end
    end

    def merged_explicit_sets(existing, incoming)
      {
        operations: merge_explicit_set("operations", existing.operations, incoming.operations,
                                       existing.operations_supplied?, incoming.operations_supplied?),
        capability_actions: merge_explicit_set("capability actions", existing.capability_actions, incoming.capability_actions,
                                               existing.capability_actions_supplied?, incoming.capability_actions_supplied?),
        auto_capability_actions: merge_explicit_set(
          "auto capability actions", existing.auto_capability_actions, incoming.auto_capability_actions,
          existing.auto_capability_actions_supplied?, incoming.auto_capability_actions_supplied?
        ),
        metrics: merge_explicit_set("metrics", existing.metric_names, incoming.metric_names,
                                    existing.metrics_supplied?, incoming.metrics_supplied?, replace: @replace_metrics),
        operations_supplied: existing.operations_supplied? || incoming.operations_supplied?,
        capability_actions_supplied: existing.capability_actions_supplied? || incoming.capability_actions_supplied?,
        auto_capability_actions_supplied: existing.auto_capability_actions_supplied? || incoming.auto_capability_actions_supplied?,
        metrics_supplied: existing.metrics_supplied? || incoming.metrics_supplied?
      }
    end

    def merge_definitions(kind, existing, incoming)
      existing.merge(incoming) do |name, established, replacement|
        raise ConfigurationError, "#{kind.capitalize} #{name} cannot be redefined incompatibly" unless established == replacement

        established
      end
    end

    def merge_value(name, established, replacement)
      return replacement unless established
      return established unless replacement
      return established if established == replacement

      raise ConfigurationError, "#{name.capitalize} cannot be redefined incompatibly"
    end

    def merge_explicit_set(name, established, replacement, established_supplied, replacement_supplied, replace: false)
      return replacement if replacement_supplied && !established_supplied
      return established if established_supplied && !replacement_supplied
      return established unless established_supplied || replacement_supplied
      return established if established == replacement
      return replacement if replace && replacement_supplied

      raise ConfigurationError, "#{name.capitalize} cannot be redefined incompatibly"
    end

    def deep_merge_hashes(base, overlay)
      base.merge(overlay) do |_key, base_value, overlay_value|
        base_value.is_a?(Hash) && overlay_value.is_a?(Hash) ? deep_merge_hashes(base_value, overlay_value) : overlay_value
      end
    end
  end
end
