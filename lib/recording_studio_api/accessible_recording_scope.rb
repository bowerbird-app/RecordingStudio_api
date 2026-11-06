# frozen_string_literal: true

module RecordingStudioApi
  class AccessibleRecordingScope
    def initialize(scope_recording:, access_recording:, include_trashed: false)
      @scope_recording = scope_recording
      @access_recording = access_recording
      @include_trashed = include_trashed
    end

    def relation
      ids = recording_ids
      return RecordingStudio::Recording.none if ids.empty?

      RecordingStudio::Recording.unscoped.where(id: ids)
    end

    def recording_ids
      @recording_ids ||= collect_accessible_recording_ids
    end

    def include?(recording_id)
      return false if recording_id.blank?

      recording_ids.map(&:to_s).include?(recording_id.to_s)
    end

    private

    attr_reader :scope_recording, :access_recording, :include_trashed

    def collect_accessible_recording_ids
      return [] if actor.nil? || scope_recording.nil?
      return [] if RecordingStudioAccessible.role_for(actor: actor, recording: recording_for_role_check).blank?

      ids = []
      queue = [scope_recording]
      seen = {}

      until queue.empty?
        recording = queue.shift
        next if recording.nil? || seen[recording.id]

        seen[recording.id] = true
        next if !include_trashed && trashed?(recording)

        ids << recording.id
        enqueue_accessible_children(queue, recording)
      end

      ids
    end

    def enqueue_accessible_children(queue, recording)
      RecordingStudioAccessible.recordings_for(
        actor: actor,
        parent_recording: recording
      ).each { |child| queue << child }

      return unless include_trashed

      trashed_children_of(recording).each { |child| queue << child }
    end

    def trashed_children_of(parent)
      RecordingStudio::Recording.unscoped
                                .where(parent_recording_id: parent.id)
                                .where.not(RecordingStudio::Recording.recording_studio_trashable_kept_sql)
    end

    def recording_for_role_check
      return scope_recording unless include_trashed && trashed?(scope_recording)

      scope_recording.parent_recording || scope_recording
    end

    def trashed?(recording)
      return false unless recording.respond_to?(:trashed_at)

      if recording.respond_to?(:recording_studio_trashable_kept?)
        !recording.recording_studio_trashable_kept?
      else
        recording.trashed_at.present?
      end
    end

    def actor
      access = access_recording&.recordable
      access.actor if access.is_a?(RecordingStudio::Access)
    end
  end
end
