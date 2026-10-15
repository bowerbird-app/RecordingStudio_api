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
            count: params[:count],
            api: api_key,
            scope_key: "client:#{api_client.id}"
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

        private

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
