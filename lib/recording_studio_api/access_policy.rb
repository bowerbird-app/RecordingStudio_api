# frozen_string_literal: true

module RecordingStudioApi
  class AccessPolicy
    def initialize(access_recording:)
      @access_recording = access_recording
    end

    def can_read?
      return false if actor.nil? || scoped_recording.nil?

      RecordingStudioAccessible.role_for(actor: actor, recording: scoped_recording).present?
    end

    def can_write?
      return false if actor.nil? || scoped_recording.nil?

      RecordingStudioAccessible.authorized?(actor: actor, recording: scoped_recording, role: :edit)
    end

    def can_admin?
      return false if actor.nil? || scoped_recording.nil?

      RecordingStudioAccessible.authorized?(actor: actor, recording: scoped_recording, role: :admin)
    end

    private

    attr_reader :access_recording

    def actor
      access = access_recording&.recordable
      access.actor if access.is_a?(RecordingStudio::Access)
    end

    def scoped_recording
      access_recording&.parent_recording || access_recording&.root_recording
    end
  end
end
