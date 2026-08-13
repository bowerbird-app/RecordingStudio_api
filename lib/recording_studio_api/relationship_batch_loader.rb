# frozen_string_literal: true

module RecordingStudioApi
  class RelationshipBatchLoader
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
          limit = entry_definition.limit
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
      table_name = @context.scoped_recordings.klass.table_name
      quoted_table = @context.scoped_recordings.connection.quote_table_name(table_name)
      order_sql = order_sql(definition, quoted_table)
      limit = definition.limit
      source = @context.scoped_recordings
                       .where(parent_recording_id: parent_ids, recordable_type: definition.child_type)
                       .reorder(Arel.sql(order_sql))
                       .select("#{quoted_table}.*, ROW_NUMBER() OVER (PARTITION BY #{quoted_table}.parent_recording_id ORDER BY #{order_sql}) AS relationship_row_number")
      @context.scoped_recordings.klass
              .from("(#{source.to_sql}) #{quoted_table}")
              .where("relationship_row_number <= ?", limit + 1)
              .preload(:recordable)
              .to_a
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
      [definition.child_type, definition.many, definition.limit, definition.order]
    end
  end
end