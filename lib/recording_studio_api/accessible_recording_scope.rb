# frozen_string_literal: true

module RecordingStudioApi
  class AccessibleRecordingScope
    def initialize(scope_recording:, access_recording:)
      @scope_recording = scope_recording
      @access_recording = access_recording
    end

    def relation
      RecordingStudio::Recording.unscoped.where(id: accessible_recording_ids)
    end

    private

    attr_reader :scope_recording, :access_recording

    def accessible_recording_ids
      @accessible_recording_ids ||= begin
        return [] if scope_recording.nil? || access_role_rank.nil?

        scope_ids = scope_recordings.map(&:id)
        scope_ids - blocked_recording_ids
      end
    end

    def blocked_recording_ids
      blocked_boundary_recordings.flat_map do |boundary_recording|
        [boundary_recording.id, *boundary_recording.descendants.map(&:id)]
      end.uniq
    end

    def blocked_boundary_recordings
      boundary_recordings = scope_recordings.drop(1).select do |recording|
        recording.recordable_type == "RecordingStudio::AccessBoundary"
      end
      return [] if boundary_recordings.empty?

      minimum_role_by_boundary_id = RecordingStudio::AccessBoundary.where(
        id: boundary_recordings.map(&:recordable_id)
      ).pluck(:id, :minimum_role).to_h

      boundary_recordings.select do |recording|
        minimum_role = minimum_role_by_boundary_id[recording.recordable_id]
        minimum_role.present? && minimum_role > access_role_rank
      end
    end

    def scope_recordings
      @scope_recordings ||= [scope_recording, *scope_recording&.descendants].compact
    end

    def access_role_rank
      @access_role_rank ||= begin
        access = access_recording&.recordable
        return unless access.is_a?(RecordingStudio::Access)

        RecordingStudio::Access.roles[access.role]
      end
    end
  end
end
