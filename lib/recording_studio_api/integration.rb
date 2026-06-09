# frozen_string_literal: true

module RecordingStudioApi
  module Integration
    module_function

    def authenticate_authorization_header(authorization_header:)
      RecordingStudioApi::Services::AuthenticateOauthAccessToken.call(
        authorization_header: authorization_header
      )
    end

    def build_access_grant(authenticated_client:)
      RecordingStudioApi::AccessGrant.new(
        api_client: authenticated_client.api_client,
        credential: authenticated_client.credential,
        access_recording: authenticated_client.access_recording,
        root_recording: authenticated_client.root_recording
      )
    end

    def access_grant_from_authorization_header(authorization_header:)
      auth_result = authenticate_authorization_header(authorization_header: authorization_header)
      return auth_result if auth_result.failure?

      RecordingStudioApi::Services::BaseService::Result.new(
        success: true,
        value: build_access_grant(authenticated_client: auth_result.value)
      )
    end

    def actor_access_recordings(actor:)
      return [] if actor.nil?

      access_ids = RecordingStudio::Access.where(actor: actor).pluck(:id)
      return [] if access_ids.empty?

      RecordingStudio::Recording.unscoped
                                .where(recordable_type: "RecordingStudio::Access", recordable_id: access_ids, trashed_at: nil)
                                .order(:created_at, :id)
                                .to_a
    end

    def resolve_access_recording_for_actor(actor:, requested_access_recording_id: nil)
      candidates = actor_access_recordings(actor: actor)
      return { recording: nil, candidates: [], error: :no_access_recordings } if candidates.empty?

      requested_id = requested_access_recording_id.to_s.presence
      if requested_id.present?
        selected = candidates.find { |recording| recording.id == requested_id }
        return { recording: selected, candidates: candidates, error: nil } if selected.present?

        return { recording: nil, candidates: candidates, error: :invalid_access_recording }
      end

      return { recording: candidates.first, candidates: candidates, error: nil } if candidates.one?

      { recording: nil, candidates: candidates, error: :selection_required }
    end

    def oauth_error_payload(error)
      RecordingStudioApi::OauthErrorMapper.payload_for(error)
    end

    def oauth_error_status(error)
      payload = oauth_error_payload(error)
      RecordingStudioApi::OauthErrorMapper.status_for(payload)
    end
  end
end