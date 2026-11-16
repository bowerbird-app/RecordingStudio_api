# frozen_string_literal: true

module RecordingStudioApi
  module Services
    module ResourceOperations
      class Index < Base
        def call
          scope_key = pagination_scope_key
          authorize_access!(access_scope_recording, role: :view)
          relation = filtered_recordings
          return paginated_json(relation, scope_key) if count_requested?

          normalized = page_request(relation, scope_key)
          known_total = fresh_total(relation, normalized)
          return { not_modified: true } if known_total == :not_modified

          paginated_json(relation, scope_key, known_total_count: known_total)
        end

        private

        def count_requested?
          RecordingStudioApi::Services::PaginateResourceCollection.flag(params[:count], name: "count")
        end

        def page_request(relation, scope_key)
          RecordingStudioApi::Services::PaginateResourceCollection.normalize_page!(
            **page_options(relation, scope_key)
          )
        end

        def fresh_total(relation, normalized)
          http = RecordingStudioApi::CollectionHttp.controller
          return nil if http.nil?

          include_total = include_total_requested?
          freshness = RecordingStudioApi::CollectionFreshness.new(
            relation: relation,
            grant_key: grant_freshness_key,
            representation: list_representation(normalized, include_total)
          )
          return :not_modified if RecordingStudioApi::CollectionFreshness.not_modified?(http, freshness)

          include_total ? freshness.total_count : nil
        end

        def paginated_json(relation, scope_key, known_total_count: nil)
          pagination = RecordingStudioApi::Services::PaginateResourceCollection.call(
            **page_options(relation, scope_key),
            count: params[:count],
            include_total: params[:include_total],
            known_total_count: known_total_count
          )
          raise RecordingStudioApi::InvalidPaginationTokenError, pagination.error if pagination.failure?

          json = pagination.value.response_body do |recordings, meta|
            relationship_context = relationship_context_for(recordings, batch: true)
            {
              resource: resource_name,
              type: recordable_type.demodulize,
              records: recordings.map { |entry| serialize_recording(entry, context: relationship_context) },
              meta: meta.merge(filter_meta)
            }
          end

          { json: json }
        end

        def page_options(relation, scope_key)
          {
            relation: relation,
            resource: resource_name,
            recordable_type: recordable_type,
            limit: params[:limit],
            pagination_token: params[:pagination_token],
            sort: params[:sort],
            order: params[:order],
            api: api_key,
            scope_key: scope_key
          }
        end

        def include_total_requested?
          RecordingStudioApi::Services::PaginateResourceCollection.flag(params[:include_total], name: "include_total")
        end

        def grant_freshness_key
          grant = access_grant
          [pagination_scope_key, grant.access_recording&.id, grant.scope_recording&.id, grant.role].join(":")
        end

        def list_representation(normalized, include_total)
          {
            "api" => api_key.to_s,
            "version" => api_version.to_s,
            "resource" => resource_name.to_s,
            "recordable_type" => recordable_type.to_s,
            "sort" => normalized.fetch(:sort),
            "order" => normalized.fetch(:order),
            "limit" => normalized.fetch(:limit),
            "pagination_token" => params[:pagination_token].to_s,
            "filter" => CollectionFilter.normalized_filters(params, recordable_type: recordable_type, api: api_key),
            "q" => params[:q].to_s,
            "include" => params[:include].to_s,
            "include_total" => include_total
          }
        end

        def filtered_recordings
          ResourceOperations.apply_list_filter(
            scoped_recordings.where(recordable_type: recordable_type),
            recordable_type: recordable_type,
            params: params,
            api: api_key
          )
        end

        def filter_meta
          {
            filter: CollectionFilter.normalized_filters(params, recordable_type: recordable_type, api: api_key),
            q: params[:q].presence
          }.compact
        end
      end
    end
  end
end
