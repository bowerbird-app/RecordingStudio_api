# frozen_string_literal: true

module RecordingStudioApi
  class AccessManagementPolicy
    def initialize(actor:)
      @actor = actor
    end

    def visible_root_recordings
      root_recordings_for(access_management_role: RecordingStudioApi.configuration.access_management_view_role)
    end

    def manageable_root_recordings
      root_recordings_for(access_management_role: RecordingStudioApi.configuration.access_management_edit_role)
    end

    def visible_access_recordings
      access_recordings_for(access_management_role: RecordingStudioApi.configuration.access_management_view_role)
    end

    def manageable_access_recordings
      access_recordings_for(access_management_role: RecordingStudioApi.configuration.access_management_edit_role)
    end

    def visible_api_client_access_recordings
      api_client_access_recordings_for(access_management_role: RecordingStudioApi.configuration.access_management_view_role)
    end

    def manageable_api_client_access_recordings
      api_client_access_recordings_for(access_management_role: RecordingStudioApi.configuration.access_management_edit_role)
    end

    def can_view_root_recording?(root_recording)
      can_view_recording?(root_recording)
    end

    def can_manage_root_recording?(root_recording)
      can_manage_recording?(root_recording)
    end

    def can_view_recording?(recording)
      authorized_root_recording?(recording, access_management_role: RecordingStudioApi.configuration.access_management_view_role)
    end

    def can_manage_recording?(recording)
      authorized_root_recording?(recording, access_management_role: RecordingStudioApi.configuration.access_management_edit_role)
    end

    def maximum_assignable_role_for(recording)
      valid_access_roles.reverse.find do |role|
        authorized_for_recording?(recording, access_management_role: role)
      end
    end

    def can_assign_role?(recording, role)
      return false unless authorized_for_recording?(
        recording,
        access_management_role: RecordingStudioApi.configuration.access_management_edit_role
      )

      requested_rank = access_role_rank(role)
      maximum_rank = access_role_rank(maximum_assignable_role_for(recording))

      requested_rank.present? && maximum_rank.present? && requested_rank <= maximum_rank
    end

    def authorized_for_root_recording?(root_recording, access_management_role:)
      authorized_for_recording?(root_recording, access_management_role: access_management_role)
    end

    def authorized_for_recording?(recording, access_management_role:)
      return false if actor.nil?
      return false if recording.nil?

      RecordingStudioAccessible.authorized?(
        actor: actor,
        recording: recording,
        role: access_management_role
      )
    end

    def authorized_root_recording?(recording, access_management_role:)
      root_recording = root_recording_for(recording)
      return false if root_recording.nil?

      root_recordings_for(access_management_role: access_management_role).any? do |candidate|
        candidate.id == root_recording.id
      end
    end

    def authorized_for_access_recording?(access_recording, access_management_role:)
      return false if actor.nil?

      authorized_recording = access_scope_recording_for(access_recording)
      return false if authorized_recording.nil?

      RecordingStudioAccessible.authorized?(
        actor: actor,
        recording: authorized_recording,
        role: access_management_role
      )
    end

    def access_recording_for(root_recording)
      return nil if root_recording.nil?

      root_id = root_recording.id
      access_recordings.find { |recording| recording.parent_recording_id == root_id || recording.root_recording&.id == root_id }
    end

    private

    attr_reader :actor

    def access_recordings_for(access_management_role:)
      access_recordings.select do |recording|
        authorized_for_access_recording?(recording, access_management_role: access_management_role)
      end
    end

    def api_client_access_recordings_for(access_management_role:)
      api_client_access_recordings.select do |recording|
        authorized_for_access_recording?(recording, access_management_role: access_management_role)
      end
    end

    def root_recordings_for(access_management_role:)
      return [] if actor.nil?

      RecordingStudioAccessible.root_recordings_for(
        actor: actor,
        minimum_role: access_management_role
      )
    end

    def access_scope_recording_for(access_recording)
      return nil if access_recording.nil?

      access_recording.parent_recording || access_recording.root_recording
    end

    def access_role_rank(role)
      RecordingStudioApi::Configuration::ACCESS_ROLE_RANKS[role.to_s.to_sym]
    end

    def valid_access_roles
      RecordingStudioApi::Configuration::ACCESS_ROLE_RANKS.keys
    end

    def root_recording_for(recording)
      return nil if recording.nil?

      recording.root_recording || recording
    end

    def access_recordings
      @access_recordings ||= begin
        access_ids = RecordingStudio::Access.where(actor: actor).pluck(:id)
        return [] if access_ids.empty?

        RecordingStudio::Recording.unscoped
                                  .includes(:recordable)
                                  .where(recordable_type: "RecordingStudio::Access", recordable_id: access_ids, trashed_at: nil)
                                  .to_a
      end
    end

    def api_client_access_recordings
      @api_client_access_recordings ||= RecordingStudio::Recording.unscoped
                                                                  .includes(:recordable)
                                                                  .where(id: RecordingStudioApi::ApiClient.select(:access_recording_id), recordable_type: "RecordingStudio::Access", trashed_at: nil)
                                                                  .to_a
    end
  end
end