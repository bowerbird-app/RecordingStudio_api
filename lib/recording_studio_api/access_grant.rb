# frozen_string_literal: true

module RecordingStudioApi
  class AccessGrant
    def initialize(api_client:, credential:, access_recording:, root_recording: nil)
      @api_client = api_client
      @credential = credential
      @access_recording = access_recording
      @root_recording = root_recording
      @accessible_scopes = {}
      @accessible_recordings = {}
      @accessible_recording_ids = {}
    end

    attr_reader :api_client, :credential, :access_recording, :root_recording

    def access
      access_recording&.recordable
    end

    def actor
      resolved_access = access
      resolved_access.actor if resolved_access.respond_to?(:actor)
    end

    def role
      resolved_access = access
      resolved_access.role if resolved_access.respond_to?(:role)
    end

    def scope_recording
      access_recording&.parent_recording || root_recording || access_recording&.root_recording
    end

    def accessible_recordings(include_trashed: false)
      @accessible_recordings[include_trashed] ||= RecordingStudio::Recording.unscoped.where(
        id: accessible_recording_ids(include_trashed: include_trashed)
      )
    end

    def accessible_recording_ids(include_trashed: false)
      @accessible_recording_ids[include_trashed] ||= accessible_scope(include_trashed: include_trashed).recording_ids
    end

    def authorized?(recording:, role:, include_trashed: false)
      return false unless recording.present?
      return false unless role_satisfies?(role)
      return false unless accessible_scope(include_trashed: include_trashed).include?(recording.id)

      recording_for_access_check = recording_for_accessible_check(recording, include_trashed: include_trashed)
      return false if actor.nil? || recording_for_access_check.nil?

      RecordingStudioAccessible.authorized?(
        actor: actor,
        recording: recording_for_access_check,
        role: role
      )
    end

    def authorize!(recording:, role:, include_trashed: false)
      return if authorized?(recording: recording, role: role, include_trashed: include_trashed)

      raise RecordingStudioApi::AuthorizationError, "API access grant is not authorized for this capability"
    end

    private

    def accessible_scope(include_trashed:)
      @accessible_scopes[include_trashed] ||= RecordingStudioApi::AccessibleRecordingScope.new(
        scope_recording: scope_recording,
        access_recording: access_recording,
        include_trashed: include_trashed
      )
    end

    def role_satisfies?(required_role)
      return false if required_role.blank?

      current_rank = access_role_rank(role)
      required_rank = access_role_rank(required_role)
      current_rank.present? && required_rank.present? && current_rank >= required_rank
    end

    def access_role_rank(role_name)
      return unless defined?(RecordingStudio::Access) && RecordingStudio::Access.respond_to?(:roles)

      RecordingStudio::Access.roles[role_name.to_s]
    end

    def recording_for_accessible_check(recording, include_trashed:)
      return recording unless include_trashed && recording.respond_to?(:trashed_at) && recording.trashed_at.present?

      recording.parent_recording || scope_recording
    end
  end
end
