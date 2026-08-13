# frozen_string_literal: true

module RecordingStudioApi
  module Services
    module ResourceOperations
      class Index < Base
        def call
          authorize_access!(access_scope_recording, role: :view)

          pagination = RecordingStudioApi::Services::PaginateResourceCollection.call(
            relation: scoped_recordings.where(recordable_type: recordable_type),
            resource: resource_name,
            recordable_type: recordable_type,
            limit: params[:limit],
            pagination_token: params[:pagination_token],
            sort: params[:sort],
            order: params[:order],
            api: api_key
          )
          raise RecordingStudioApi::InvalidPaginationTokenError, pagination.error if pagination.failure?

          payload = pagination.value
          recordings = payload.fetch(:rows)
          relationship_context = relationship_context_for(recordings)

          {
            json: {
              resource: resource_name,
              type: recordable_type.demodulize,
              records: recordings.map { |entry| serialize_recording(entry, context: relationship_context) },
              meta: payload.fetch(:meta)
            }
          }
        end
      end
    end
  end
end