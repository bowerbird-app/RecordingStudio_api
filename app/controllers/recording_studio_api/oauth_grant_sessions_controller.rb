# frozen_string_literal: true

module RecordingStudioApi
  class OauthGrantSessionsController < RecordingStudioApi::ApplicationController
    before_action :authenticate_user!, if: -> { respond_to?(:authenticate_user!, true) }
    before_action :load_actor_access_recordings

    def index
      @selected_access_recording = resolve_selected_access_recording
      return if performed?
      @can_manage_selected_access_recording = @selected_access_recording.present? && access_management_policy.can_manage_root_recording?(@selected_access_recording.root_recording)

      @access_options = @actor_access_recordings.map { |recording| [access_recording_label(recording), recording.id] }
      @session_rows = active_sessions_for(@selected_access_recording).map do |session|
        {
          id: session.id,
          app: session.oauth_client&.name || "Unknown",
          created_at: timestamp(session.created_at),
          last_used_at: timestamp(session.last_used_at),
          status: session.revoked_at.present? ? "Revoked" : "Active"
        }
      end
    end

    def revoke
      session = RecordingStudioApi::OauthGrantSession.find_by(id: params[:id])
      return head :not_found if session.nil?
      return head :forbidden unless access_management_policy.can_manage_root_recording?(session.access_recording.root_recording)

      session.revoke_family!
      redirect_to oauth_grant_sessions_path(access_recording_id: session.access_recording_id), notice: "OAuth grant session revoked."
    end

    private

    def load_actor_access_recordings
      actor = current_request_actor
      return head :unauthorized if actor.nil?

      access_ids = RecordingStudio::Access.where(actor: actor).pluck(:id)
      @actor_access_recordings = if access_ids.empty?
                                   []
                                 else
                                   RecordingStudio::Recording.unscoped.where(
                                     recordable_type: "RecordingStudio::Access",
                                     recordable_id: access_ids,
                                     trashed_at: nil
                                   ).order(:created_at, :id).to_a
                                 end
    end

    def resolve_selected_access_recording
      return render_empty_state if @actor_access_recordings.empty?

      requested_id = params[:access_recording_id].to_s.presence
      return @actor_access_recordings.first if requested_id.blank?

      selected = @actor_access_recordings.find { |recording| recording.id == requested_id }
      return selected if selected.present?

      head :forbidden
    end

    def render_empty_state
      @access_options = []
      @selected_access_recording = nil
      @session_rows = []
    end

    def active_sessions_for(access_recording)
      RecordingStudioApi::OauthGrantSession
        .includes(:oauth_client)
        .where(access_recording_id: access_recording.id, revoked_at: nil)
        .order(created_at: :desc)
    end

    def timestamp(value)
      return "Never" if value.blank?

      value.in_time_zone.strftime("%Y-%m-%d %H:%M")
    end

    def access_recording_label(recording)
      parent = recording.parent_recording
      return "Access #{recording.id.first(8)}" if parent.nil? || parent.recordable.nil?

      "#{parent.recordable.class.name.demodulize} - #{recordable_identifier(parent.recordable)}"
    end

    def recordable_identifier(recordable)
      return recordable.name if recordable.respond_to?(:name) && recordable.name.present?
      return recordable.title if recordable.respond_to?(:title) && recordable.title.present?

      "##{recordable.id}"
    end

    def current_request_actor
      return current_user if respond_to?(:current_user, true) && current_user.present?
      return Current.actor if defined?(Current) && Current.respond_to?(:actor)

      nil
    end

    def access_management_policy
      @access_management_policy ||= RecordingStudioApi::AccessManagementPolicy.new(actor: current_request_actor)
    end
  end
end
