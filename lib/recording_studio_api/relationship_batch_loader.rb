# frozen_string_literal: true

module RecordingStudioApi
  class RelationshipBatchLoader
    # Included child collections return at most this many rows per parent.
    # A relationship limit lower than this still applies. Documented in the README.
    def self.max_included_children
      100
    end

    def initialize(context:, entries:)
      @context = context
      @entries = entries
      @prepared = {}
    end

    def call
      load_children
      load_custom
      @prepared
    end

    private

    def load_children
      child_entries.group_by { |_parent, _name, definition| child_key(definition) }.each_value do |entries|
        definition = entries.first.last
        rows = bounded_children(entries.map { |parent, _name, _definition| parent.id }.uniq, definition)
               .group_by(&:parent_recording_id)
               .transform_values { |children| children.sort_by { |child| child[:relationship_row_number].to_i } }
        entries.each do |parent, name, entry_definition|
          children = rows.fetch(parent.id, [])
          @context.authorize_relationship!(parent, name, entry_definition)
          values = @context.authorized_targets(children, parent, name, entry_definition)
          limit = window_size(entry_definition)
          @prepared[[parent.id, name.to_s]] = {
            value: entry_definition.many ? values.first(limit) : values.first,
            meta: entry_definition.many && values.length > limit ? { limit: limit, has_more: true } : nil
          }
        end
      end
    end

    def load_custom
      custom_entries.group_by { |_parent, name, definition| [name.to_s, definition, definition.resolver] }.each_value do |entries|
        definition = entries.first.last
        resolver = definition.resolver
        raise ConfigurationError, "Custom relationship #{entries.first[1]} requires resolver.call_many(contexts) for index expansion" unless resolver.respond_to?(:call_many)

        contexts = entries.map { |parent, name, entry_definition| @context.resolver_context(parent, entry_definition, name: name) }
        values = resolver.call_many(contexts)
        validate_many_result!(values, entries, definition)
        entries.each do |parent, name, entry_definition|
          @prepared[[parent.id, name.to_s]] = {
            value: @context.normalize_custom_value(values[parent.id], parent, name, entry_definition),
            meta: nil
          }
        end
      end
    end

    def bounded_children(parent_ids, definition)
      return [] if parent_ids.empty?

      recordings = @context.scoped_recordings.klass
      connection = recordings.connection
      quoted_table = connection.quote_table_name(recordings.table_name)
      order = order_sql(definition, quoted_table)
      fetch_count = definition.many ? window_size(definition) + 1 : 1
      values_sql = parent_ids.map { |id| "(#{connection.quote(id)}::uuid)" }.join(", ")
      lateral = <<~SQL.squish
        SELECT #{quoted_table}.*,
               ROW_NUMBER() OVER (ORDER BY #{order}) AS relationship_row_number
        FROM #{quoted_table}
        WHERE #{quoted_table}.parent_recording_id = page_parent.id
          AND #{quoted_table}.recordable_type = #{connection.quote(definition.child_type)}
          #{scope_predicate(quoted_table)}
        ORDER BY #{order}
        LIMIT #{fetch_count.to_i}
      SQL
      source = <<~SQL.squish
        SELECT page_child.*
        FROM (VALUES #{values_sql}) AS page_parent(id)
        JOIN LATERAL (#{lateral}) page_child ON TRUE
      SQL

      recordings.unscoped
                .from("(#{source}) #{quoted_table}")
                .preload(:recordable)
                .to_a
    end

    # The page ids are already inside the caller's scope. Direct children
    # still have to pass that same relation, so a row outside it cannot appear.
    def scope_predicate(quoted_table)
      scope = @context.scoped_recordings
      allowed_ids = scope.unscope(:order, :limit, :offset).select(:id).to_sql
      "AND #{quoted_table}.id IN (#{allowed_ids})"
    end

    def window_size(definition)
      return 1 unless definition.many

      requested = definition.limit.to_i
      requested = 1 if requested < 1
      [requested, self.class.max_included_children].min
    end

    def order_sql(definition, quoted_table)
      order = definition.order
      order = { "created_at" => :asc } if order.empty?
      order = order.merge("id" => :asc) unless order.key?("id")
      order.map do |column, direction|
        raise ConfigurationError, "Unsupported direct-child order column #{column}" unless RecordableRegistration::DIRECT_CHILD_ORDER_ATTRIBUTES.include?(column)
        raise ConfigurationError, "Unsupported direct-child order direction #{direction}" unless %i[asc desc].include?(direction)

        quoted_column = @context.scoped_recordings.connection.quote_column_name(column)
        "#{quoted_table}.#{quoted_column} #{direction == :desc ? 'DESC' : 'ASC'}"
      end.join(", ")
    end

    def validate_many_result!(values, entries, _definition)
      raise ConfigurationError, "Custom relationship #{entries.first[1]} call_many must return a hash keyed by primary recording id" unless values.is_a?(Hash)

      ids = entries.map { |parent, _name, _definition| parent.id }
      return if (values.keys - ids).empty? && values.values.all? { |value| value.nil? || @context.recording?(value) || @context.collection?(value) }

      raise ConfigurationError, "Custom relationship #{entries.first[1]} call_many returned an invalid key or value"
    end

    def child_entries
      @child_entries ||= @entries.select { |_parent, _name, definition| definition.source == :children }
    end

    def custom_entries
      @custom_entries ||= @entries.select { |_parent, _name, definition| definition.source == :custom }
    end

    def child_key(definition)
      [definition.child_type, definition.many, window_size(definition), definition.order]
    end
  end
end