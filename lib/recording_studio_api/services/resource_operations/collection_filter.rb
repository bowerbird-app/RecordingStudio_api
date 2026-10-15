# frozen_string_literal: true

module RecordingStudioApi
  module Services
    module ResourceOperations
      module CollectionFilter
        module_function

        def apply(relation, recordable_type:, params:, api:)
          filtered = apply_attribute_filters(relation, recordable_type: recordable_type, params: params, api: api)
          apply_search_query(filtered, recordable_type: recordable_type, params: params, api: api)
        end

        def normalized_filters(params, recordable_type:, api:)
          raw = params[:filter]
          return {} if raw.blank?

          filter_hash =
            if raw.respond_to?(:to_unsafe_h)
              raw.to_unsafe_h
            elsif raw.respond_to?(:to_h)
              raw.to_h
            else
              {}
            end

          allowed = filterable_attributes(recordable_type, api)
          filter_hash.each_with_object({}) do |(key, value), filters|
            attribute = key.to_s
            next unless allowed.include?(attribute)
            next if value.nil? || value.to_s.strip.empty?

            filters[attribute] = value
          end
        end

        def apply_attribute_filters(relation, recordable_type:, params:, api:)
          filters = normalized_filters(params, recordable_type: recordable_type, api: api)
          return relation if filters.empty?

          recordable_klass = recordable_type.safe_constantize
          return relation if recordable_klass.nil?

          table = recordable_klass.arel_table
          joined = with_recordable_join(relation, recordable_klass, recordable_type)
          filters.reduce(joined) do |current, (attribute, value)|
            current.where(table[attribute].eq(value))
          end
        end

        def apply_search_query(relation, recordable_type:, params:, api:)
          query = params[:q].to_s.strip
          return relation if query.blank?

          searchable = filterable_attributes(recordable_type, api)
          return relation if searchable.empty?

          recordable_klass = recordable_type.safe_constantize
          return relation if recordable_klass.nil?

          table = recordable_klass.arel_table
          joined = with_recordable_join(relation, recordable_klass, recordable_type)
          pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
          conditions = searchable.map { |attribute| table[attribute].matches(pattern) }
          joined.where(conditions.reduce { |left, right| left.or(right) })
        end

        def filterable_attributes(recordable_type, api)
          registration = RecordingStudioApi.recordable_registration_for(recordable_type, api: api)
          return [] if registration.nil?

          registration.filterable_attributes
        end

        def with_recordable_join(relation, recordable_klass, recordable_type)
          table_name = recordable_klass.table_name
          already_joined = relation.joins_values.any? { |join| join.to_s.include?(table_name) }
          return relation if already_joined

          relation.joins(recordable_join_sql(recordable_klass, recordable_type))
        end

        def recordable_join_sql(recordable_klass, recordable_type)
          recordings = RecordingStudio::Recording.table_name
          recordables = recordable_klass.table_name
          <<~SQL.squish
            INNER JOIN #{recordables}
              ON #{recordables}.id = #{recordings}.recordable_id
             AND #{recordings}.recordable_type = #{RecordingStudio::Recording.connection.quote(recordable_type)}
          SQL
        end

        private_class_method :apply_attribute_filters, :apply_search_query, :filterable_attributes,
                             :with_recordable_join, :recordable_join_sql
      end
      private_constant :CollectionFilter

      def self.apply_list_filter(relation, recordable_type:, params:, api:)
        CollectionFilter.apply(relation, recordable_type: recordable_type, params: params, api: api)
      end
    end
  end
end
