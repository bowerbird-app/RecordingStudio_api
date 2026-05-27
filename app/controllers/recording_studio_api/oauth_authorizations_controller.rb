# frozen_string_literal: true

module RecordingStudioApi
  class OauthAuthorizationsController < RecordingStudioApi::ApplicationController
    before_action :authenticate_user!, only: :new, if: -> { respond_to?(:authenticate_user!, true) }

    def new
      resolved_access_recording = resolve_authorize_access_recording
      return if performed?

      result = RecordingStudioApi::Services::AuthorizeOauthClient.call(
        response_type: params[:response_type].to_s,
        client_id: params[:client_id].to_s,
        redirect_uri: params[:redirect_uri].to_s,
        code_challenge: params[:code_challenge].to_s,
        code_challenge_method: params[:code_challenge_method].to_s,
        access_recording_id: resolved_access_recording.id,
        state: params[:state].presence
      )

      if result.failure?
        render_oauth_error(result.error)
      else
        authorization_payload = result.value
        redirect_params = {
          code: authorization_payload.fetch(:code),
          state: authorization_payload[:state]
        }.compact

        redirect_to("#{authorization_payload.fetch(:redirect_uri)}?#{redirect_params.to_query}", allow_other_host: true)
      end
    end

    private

    def render_oauth_error(error)
      payload = RecordingStudioApi::OauthErrorMapper.payload_for(error)
      status = RecordingStudioApi::OauthErrorMapper.status_for(payload)
      render json: payload, status: status
    end

    def resolve_authorize_access_recording
      actor = current_request_actor
      return render_oauth_error(error_payload("access_denied", "user authentication is required")) if actor.nil?

      accessible_recordings = actor_access_recordings(actor)
      return render_oauth_error(error_payload("invalid_scope", "no active access recording is available for actor")) if accessible_recordings.empty?

      requested_access_recording_id = params[:access_recording_id].to_s.presence
      if requested_access_recording_id.present?
        resolved = accessible_recordings.find { |recording| recording.id == requested_access_recording_id }
        return resolved if resolved.present?

        return render_oauth_error(error_payload("invalid_scope", "access recording is not available for actor"))
      end

      return accessible_recordings.first if accessible_recordings.one?

      @authorize_access_recordings = accessible_recordings
      @authorize_access_options = accessible_recordings.map do |recording|
        [access_recording_label(recording), recording.id]
      end
      @authorize_form_values = {
        response_type: params[:response_type].to_s,
        client_id: params[:client_id].to_s,
        redirect_uri: params[:redirect_uri].to_s,
        code_challenge: params[:code_challenge].to_s,
        code_challenge_method: params[:code_challenge_method].to_s,
        state: params[:state].presence
      }

      render :new, status: :ok
    end

    def actor_access_recordings(actor)
      access_ids = RecordingStudio::Access.where(actor: actor).pluck(:id)
      return [] if access_ids.empty?

      RecordingStudio::Recording.unscoped
                                .where(recordable_type: "RecordingStudio::Access", recordable_id: access_ids, trashed_at: nil)
                                .to_a
    end

    def current_request_actor
      return current_user if respond_to?(:current_user, true) && current_user.present?
      return Current.actor if defined?(Current) && Current.respond_to?(:actor)

      nil
    end

    def error_payload(code, description)
      { error: code, error_description: description }
    end

    def access_recording_label(recording)
      parent = recording.parent_recording
      if parent.nil? || parent.recordable.nil?
        "Access #{recording.id.first(8)}"
      else
        "#{parent.recordable.class.name.demodulize} - #{recordable_identifier(parent.recordable)}"
      end
    end

    def recordable_identifier(recordable)
      return recordable.name if recordable.respond_to?(:name) && recordable.name.present?
      return recordable.title if recordable.respond_to?(:title) && recordable.title.present?

      "##{recordable.id}"
    end
  end
end
