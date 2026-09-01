# frozen_string_literal: true

module RecordingStudioApi
  module Integration
    module_function

    def authenticate_authorization_header(authorization_header:, api: :public)
      RecordingStudioApi::Services::AuthenticateOauthAccessToken.call(
        authorization_header: authorization_header,
        api: api
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

    def access_grant_from_authorization_header(authorization_header:, api: :public)
      auth_result = authenticate_authorization_header(authorization_header: authorization_header, api: api)
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

    def connect_access_recordings(actor:)
      actor_access_recordings(actor: actor).select { |recording| connectable_access_parent?(recording) }
    end

    def resolve_access_recording_for_actor(actor:, requested_access_recording_id: nil, connect: false)
      candidates = connect ? connect_access_recordings(actor: actor) : actor_access_recordings(actor: actor)
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

    def connectable_access_parent?(access_recording)
      parent = access_recording.parent_recording
      return false if parent.nil?
      return false if parent.recordable_type == "RecordingStudio::Access"
      return false if admin_root_recordable_type?(parent.recordable_type)

      true
    end

    def admin_root_recordable_type?(recordable_type)
      Array(RecordingStudioApi.configuration.admin_root_recordable_type_names).map(&:to_s).include?(recordable_type.to_s)
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