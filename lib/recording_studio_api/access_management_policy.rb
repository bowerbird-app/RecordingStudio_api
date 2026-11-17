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
      return [] if actor.nil?

      role = edit_role
      root_recordings_for(access_management_role: role).select do |root|
        authorized_recording_ids_for(root, access_management_role: role).where(id: root.id).exists?
      end
    end

    # Recordings this actor can manage. Roots come from workspace membership.
    # The rows come from Accessible's authorized_recordings for the edit role.
    def manageable_recordings(recordable_types: nil, roots: nil)
      anchors = manageable_anchors(roots)
      return [] if anchors.empty?

      scope = kept_recordings_for(recordable_types)
      anchors.flat_map do |anchor|
        authorized_recording_rows(anchor, scope: scope, access_management_role: edit_role)
      end.uniq(&:id)
    end

    def can_manage_any_recording?
      return false if actor.nil?

      role = edit_role
      root_recordings_for(access_management_role: role).any? do |root|
        authorized_recording_ids_for(root, access_management_role: role).exists?
      end
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
      authorized_for_recording?(recording, access_management_role: view_role)
    end

    def can_manage_recording?(recording)
      authorized_for_recording?(recording, access_management_role: edit_role)
    end

    def maximum_assignable_role_for(recording)
      valid_access_roles.reverse.find do |role|
        authorized_for_recording?(recording, access_management_role: role)
      end
    end

    def can_assign_role?(recording, role)
      return false unless can_manage_recording?(recording)

      RecordingStudio::AccessRoles.satisfies?(
        role: maximum_assignable_role_for(recording),
        minimum_role: role
      )
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

    def valid_access_roles
      RecordingStudio::AccessRoles::ORDER.keys.map(&:to_sym)
    end

    def view_role
      RecordingStudioApi.configuration.access_management_view_role
    end

    def edit_role
      RecordingStudioApi.configuration.access_management_edit_role
    end

    def manageable_anchors(roots)
      return [] if actor.nil?

      anchors = Array(roots).compact
      return anchors if anchors.any?

      root_recordings_for(access_management_role: edit_role)
    end

    def kept_recordings_for(recordable_types)
      scope = RecordingStudio::Recording.unscoped.kept
      return scope if recordable_types.blank?

      scope.where(recordable_type: recordable_types)
    end

    def authorized_recording_ids_for(recording, access_management_role:)
      RecordingStudioAccessible.authorized_recording_ids(
        actor: actor,
        root: recording,
        role: access_management_role
      )
    end

    def authorized_recording_rows(recording, scope:, access_management_role:)
      RecordingStudioAccessible.authorized_recordings(
        actor: actor,
        root: recording,
        scope: scope,
        role: access_management_role
      ).includes(:recordable).reorder(:created_at, :id).to_a
    end

    def access_recordings
      @access_recordings ||= begin
        access_ids = RecordingStudio::Access.where(actor: actor).pluck(:id)
        return [] if access_ids.empty?

        RecordingStudio::Recording.unscoped
                                  .includes(:recordable)
                                  .where(recordable_type: "RecordingStudio::Access", recordable_id: access_ids)
                                  .kept
                                  .to_a
      end
    end

    def api_client_access_recordings
      @api_client_access_recordings ||= RecordingStudio::Recording.unscoped
                                                                  .includes(:recordable)
                                                                  .where(id: RecordingStudioApi::ApiClient.select(:access_recording_id), recordable_type: "RecordingStudio::Access")
                                                                  .kept
                                                                  .to_a
    end
  end
end