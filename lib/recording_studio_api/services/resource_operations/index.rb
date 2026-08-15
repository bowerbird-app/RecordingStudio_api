# frozen_string_literal: true

module RecordingStudioApi
  module Services
    module ResourceOperations
      class Index < Base
        def call
          authorize_access!(access_scope_recording, role: :view)

          pagination = RecordingStudioApi::Services::PaginateResourceCollection.call(
            relation: filtered_recordings,
            resource: resource_name,
            recordable_type: recordable_type,
            limit: params[:limit],
            pagination_token: params[:pagination_token],
            sort: params[:sort],
            order: params[:order],
            api: api_key,
            scope_key: "client:#{api_client.id}"
          )
          raise RecordingStudioApi::InvalidPaginationTokenError, pagination.error if pagination.failure?

          payload = pagination.value
          recordings = payload.fetch(:rows)
          relationship_context = relationship_context_for(recordings, batch: true)

          {
            json: {
              resource: resource_name,
              type: recordable_type.demodulize,
              records: recordings.map { |entry| serialize_recording(entry, context: relationship_context) },
              meta: payload.fetch(:meta).merge(filter_meta)
            }
          }
        end

        private

        def filtered_recordings
          relation = scoped_recordings.where(recordable_type: recordable_type)
          relation = apply_attribute_filters(relation)
          apply_search_query(relation)
        end

        def apply_attribute_filters(relation)
          filters = normalized_filters
          return relation if filters.empty?

          recordable_klass = recordable_type.safe_constantize
          return relation if recordable_klass.nil?

          table = recordable_klass.arel_table
          joined = with_recordable_join(relation, recordable_klass)
          filters.reduce(joined) do |current, (attribute, value)|
            current.where(table[attribute].eq(value))
          end
        end

        def apply_search_query(relation)
          query = params[:q].to_s.strip
          return relation if query.blank?

          searchable = filterable_attributes
          return relation if searchable.empty?

          recordable_klass = recordable_type.safe_constantize
          return relation if recordable_klass.nil?

          table = recordable_klass.arel_table
          joined = with_recordable_join(relation, recordable_klass)
          pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
          conditions = searchable.map { |attribute| table[attribute].matches(pattern) }
          joined.where(conditions.reduce { |left, right| left.or(right) })
        end

        def with_recordable_join(relation, recordable_klass)
          table_name = recordable_klass.table_name
          already_joined = relation.joins_values.any? { |join| join.to_s.include?(table_name) }
          return relation if already_joined

          relation.joins(recordable_join_sql(recordable_klass))
        end

        def normalized_filters
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

          allowed = filterable_attributes
          filter_hash.each_with_object({}) do |(key, value), filters|
            attribute = key.to_s
            next unless allowed.include?(attribute)
            next if value.nil? || value.to_s.strip.empty?

            filters[attribute] = value
          end
        end

        def filterable_attributes
          registration = RecordingStudioApi.recordable_registration_for(recordable_type, api: api_key)
          return [] if registration.nil?

          # Prefer attributes hosts marked sortable/writable; both are safe query surfaces.
          (registration.sortable_attributes | registration.writable_attributes).map(&:to_s)
        end

        def filter_meta
          {
            filter: normalized_filters,
            q: params[:q].presence
          }.compact
        end

        def recordable_join_sql(recordable_klass)
          recordings = RecordingStudio::Recording.table_name
          recordables = recordable_klass.table_name
          <<~SQL.squish
            INNER JOIN #{recordables}
              ON #{recordables}.id = #{recordings}.recordable_id
             AND #{recordings}.recordable_type = #{RecordingStudio::Recording.connection.quote(recordable_type)}
          SQL
        end
      end
    end
  end
end
